package secrets

import (
	"context"
	"fmt"
	"sync"
	"sync/atomic"
	"time"
)

type cacheItem struct {
	value     string
	versionID string
	expiresAt time.Time
}

// Metrics tracks cache performance.
type Metrics struct {
	Hits     uint64 `json:"hits"`
	Misses   uint64 `json:"misses"`
	Expiries uint64 `json:"expiries"`
}

// MemoryCache provides a thread-safe TTL cache with background cleanup and stale-while-revalidate behavior.
type MemoryCache struct {
	mu         sync.RWMutex
	items      map[string]*cacheItem
	ttl        time.Duration
	maxSize    int
	hits       uint64
	misses     uint64
	expiries   uint64
	fetcher    func(ctx context.Context, key string) (string, string, error)
	reaperStop chan struct{}
}

// NewMemoryCache initializes an in-memory TTL secret cache.
func NewMemoryCache(ttl time.Duration, maxSize int, fetcher func(ctx context.Context, key string) (string, string, error)) *MemoryCache {
	if maxSize <= 0 {
		maxSize = 100
	}
	c := &MemoryCache{
		items:      make(map[string]*cacheItem),
		ttl:        ttl,
		maxSize:    maxSize,
		fetcher:    fetcher,
		reaperStop: make(chan struct{}),
	}

	go c.startReaper(30 * time.Second)
	return c
}

// Close stops the background reaper.
func (c *MemoryCache) Close() {
	close(c.reaperStop)
}

// Get returns the cached value or fetches it if missing/expired.
// On expired hit, returns stale value and triggers an async background refresh.
func (c *MemoryCache) Get(ctx context.Context, key string) (string, string, error) {
	c.mu.RLock()
	item, exists := c.items[key]
	c.mu.RUnlock()

	now := time.Now()

	if exists {
		if now.Before(item.expiresAt) {
			atomic.AddUint64(&c.hits, 1)
			return item.value, item.versionID, nil
		}

		// Stale hit: return stale value immediately, trigger async refresh
		atomic.AddUint64(&c.hits, 1)
		atomic.AddUint64(&c.expiries, 1)
		go func() {
			bgCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()
			_, _, _ = c.FetchAndSet(bgCtx, key)
		}()
		return item.value, item.versionID, nil
	}

	// Cache miss
	atomic.AddUint64(&c.misses, 1)
	return c.FetchAndSet(ctx, key)
}

// FetchAndSet invokes the fetcher and updates the cache.
func (c *MemoryCache) FetchAndSet(ctx context.Context, key string) (string, string, error) {
	if c.fetcher == nil {
		return "", "", fmt.Errorf("no fetcher defined for cache")
	}

	val, ver, err := c.fetcher(ctx, key)
	if err != nil {
		return "", "", err
	}

	c.mu.Lock()
	defer c.mu.Unlock()

	// Enforce max entries cap
	if len(c.items) >= c.maxSize && c.items[key] == nil {
		// Evict an arbitrary item if full
		for k := range c.items {
			delete(c.items, k)
			break
		}
	}

	c.items[key] = &cacheItem{
		value:     val,
		versionID: ver,
		expiresAt: time.Now().Add(c.ttl),
	}

	return val, ver, nil
}

// Invalidate removes a key from cache.
func (c *MemoryCache) Invalidate(key string) {
	c.mu.Lock()
	delete(c.items, key)
	c.mu.Unlock()
}

// GetMetrics returns snapshot of hit, miss, and expiry metrics.
func (c *MemoryCache) GetMetrics() Metrics {
	return Metrics{
		Hits:     atomic.LoadUint64(&c.hits),
		Misses:   atomic.LoadUint64(&c.misses),
		Expiries: atomic.LoadUint64(&c.expiries),
	}
}

func (c *MemoryCache) startReaper(interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			now := time.Now()
			c.mu.Lock()
			for k, item := range c.items {
				if now.After(item.expiresAt.Add(5 * time.Minute)) { // Hard eviction 5 min post TTL
					delete(c.items, k)
				}
			}
			c.mu.Unlock()
		case <-c.reaperStop:
			return
		}
	}
}
