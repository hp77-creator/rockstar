# SQLite Storage Optimizations

This document outlines the performance optimizations implemented in the SQLite storage layer and their impact on various operations.

## Optimizations Applied

### 1. Write-Ahead Logging (WAL)
- Enabled WAL mode for better concurrency and write performance
- Allows multiple readers with a single writer
- Provides better crash recovery
```sql
PRAGMA journal_mode = WAL;
```

### 2. Memory & Cache Settings
- Increased SQLite page cache to 16MB
- Enabled memory-mapped I/O for better read performance
```sql
PRAGMA cache_size = -4000;       -- 16MB (4000 pages * 4KB per page)
PRAGMA mmap_size = 268435456;    -- 256MB for memory-mapped I/O
```

### 3. Synchronization Settings
- Optimized for performance while maintaining durability
```sql
PRAGMA synchronous = NORMAL;     -- Safe in WAL mode
PRAGMA busy_timeout = 5000;      -- 5 second timeout for busy connections
```

### 4. Indexing
- Added indexes for frequently accessed columns
```sql
CREATE INDEX idx_clips_content_hash ON clip_models(content_hash);
CREATE INDEX idx_clips_last_used ON clip_models(last_used);
```

### 5. Connection Pool Configuration
```go
sqlDB.SetMaxOpenConns(1)        // SQLite supports one writer at a time
sqlDB.SetMaxIdleConns(1)
sqlDB.SetConnMaxLifetime(time.Hour)
```

## Performance Benchmarks

All benchmarks were run on Apple M1 Pro processor with the following test data:
- Single record size: 1KB
- Bulk operations: 100 records per transaction

### Single Operations
| Operation | Time per Operation | Memory per Operation | Allocations |
|-----------|-------------------|---------------------|-------------|
| Store     | 116 μs           | 27.5 KB            | 330         |
| Get       | 114 μs           | 27.4 KB            | 330         |
| List      | 36 μs            | 16.2 KB            | 144         |

### Bulk Operations
| Operation  | Time per Operation | Memory per Operation | Allocations |
|------------|-------------------|---------------------|-------------|
| BulkStore  | 5.04 ms          | 941 KB             | 19,826      |
| Per Record | ~50 μs           | ~9.4 KB            | ~198        |

## Key Findings

1. **Bulk Operations Efficiency**
   - Bulk storing is more efficient per record (~50μs) compared to individual stores (116μs)
   - Memory usage in bulk operations is optimized due to transaction reuse

2. **Read Performance**
   - List operations are fastest (36μs) due to memory-mapped I/O and indexing
   - Get operations benefit from the increased cache size

3. **Memory Usage**
   - Single operations maintain consistent memory usage (~27KB)
   - Bulk operations use more total memory but less per record

## References

1. [SQLite WAL Mode Documentation](https://sqlite.org/wal.html)
2. [SQLite Performance Optimization](https://sqlite.org/speed.html)
3. [SQLite Pragma Statements](https://sqlite.org/pragma.html)
4. [GORM Documentation](https://gorm.io/docs/)

## Running Benchmarks

To run these benchmarks yourself:

```bash
cd internal/storage/sqlite
go test -bench=. -benchmem
```
