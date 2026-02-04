## API Benchmarks

Benchmarks of modern web frameworks.

### Results 

**Duration:** 10s per endpoint

**Connections:** 200

#### Requests/sec

  | Endpoint | Rust Axum | JS Bun | Go Chi | Java Quarkus | Python Django |
  |----------|-------:|-------:|-------:|-------:|-------:|
  | GET /api/health | 409,068 | 319,990 | 259,217 | 257,907 | 26,954 |
  | GET /api/books | 212,515 | 215,535 | 144,925 | 54,986 | 16,724 |
  | GET /api/books/3 | 225,578 | 232,056 | 174,764 | 57,863 | 17,011 |

  #### Average Latency

  | Endpoint | Rust Axum | JS Bun | Go Chi | Java Quarkus | Python Django |
  |----------|-------:|-------:|-------:|-------:|-------:|
  | GET /api/health | 0.4871 ms | 0.6223 ms | 0.7687 ms | 0.7726 ms | 7.4045 ms |
  | GET /api/books | 0.9367 ms | 0.9245 ms | 1.3757 ms | 3.6295 ms | 11.9360 ms |
  | GET /api/books/3 | 0.8824 ms | 0.8587 ms | 1.1407 ms | 3.4493 ms | 11.7345 ms |

  #### p99 Latency

  | Endpoint | Rust Axum | JS Bun | Go Chi | Java Quarkus | Python Django |
  |----------|-------:|-------:|-------:|-------:|-------:|
  | GET /api/health | 1.3236 ms | 7.0605 ms | 4.2105 ms | 3.3896 ms | 12.6313 ms |
  | GET /api/books | 2.4998 ms | 6.3534 ms | 6.2153 ms | 13.9007 ms | 15.0192 ms |
  | GET /api/books/3 | 2.4199 ms | 6.4179 ms | 4.6881 ms | 11.5347 ms | 14.9445 ms |


### Disclaimer

This is a contrived (and poorly made) demo. Results will _obviously_ differ in real world usage.

I would highly recommend Tech Empower's [Web Framework Benchmarks](https://www.techempower.com/benchmarks/#section=data-r23)  if you want more reliable benchmark results.
