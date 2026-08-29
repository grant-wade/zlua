#define _POSIX_C_SOURCE 200809L

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifdef __APPLE__
#include <mach/mach_time.h>
#endif

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#define PHASE_COUNT 7

enum phase {
  PHASE_NEWSTATE,
  PHASE_OPENLIBS,
  PHASE_STARTUP_TOTAL,
  PHASE_LOAD,
  PHASE_CALL,
  PHASE_CLOSE,
  PHASE_FIRST_CHUNK,
};

static const char *phase_names[PHASE_COUNT] = {
  "newstate", "openlibs", "startup-total", "load", "call", "close", "first-chunk",
};

struct alloc_stats {
  uint64_t allocations;
  uint64_t resizes;
  uint64_t requested_bytes;
  uint64_t live_bytes;
  uint64_t peak_bytes;
  uint64_t phase_peak_bytes;
};

struct alloc_snapshot {
  uint64_t allocations;
  uint64_t resizes;
  uint64_t requested_bytes;
  uint64_t live_bytes;
};

struct metric {
  uint64_t elapsed_ns;
  uint64_t allocations;
  uint64_t resizes;
  uint64_t requested_bytes;
  uint64_t live_bytes;
  uint64_t peak_bytes;
};

struct sample {
  struct metric phases[PHASE_COUNT];
};

static uint64_t now_ns(void) {
#ifdef __APPLE__
  static mach_timebase_info_data_t timebase;
  if (timebase.denom == 0 && mach_timebase_info(&timebase) != KERN_SUCCESS) abort();
  uint64_t ticks = mach_absolute_time();
  return (ticks / timebase.denom) * timebase.numer +
      ((ticks % timebase.denom) * timebase.numer) / timebase.denom;
#else
  struct timespec time;
  if (clock_gettime(CLOCK_MONOTONIC, &time) != 0) abort();
  return (uint64_t)time.tv_sec * UINT64_C(1000000000) + (uint64_t)time.tv_nsec;
#endif
}

static void update_size(struct alloc_stats *stats, size_t old_size, size_t new_size) {
  if (new_size >= old_size) {
    uint64_t growth = (uint64_t)(new_size - old_size);
    stats->live_bytes += growth;
    stats->requested_bytes += growth;
  } else {
    stats->live_bytes -= (uint64_t)(old_size - new_size);
  }
  if (stats->live_bytes > stats->peak_bytes) stats->peak_bytes = stats->live_bytes;
  if (stats->live_bytes > stats->phase_peak_bytes) stats->phase_peak_bytes = stats->live_bytes;
}

static void *counting_alloc(void *ud, void *ptr, size_t old_size, size_t new_size) {
  struct alloc_stats *stats = (struct alloc_stats *)ud;
  if (new_size == 0) {
    free(ptr);
    if (ptr != NULL) stats->live_bytes -= (uint64_t)old_size;
    return NULL;
  }
  if (ptr == NULL) {
    void *result = malloc(new_size);
    if (result != NULL) {
      stats->allocations++;
      update_size(stats, 0, new_size);
    }
    return result;
  }

  void *result = realloc(ptr, new_size);
  if (result != NULL) {
    stats->resizes++;
    update_size(stats, old_size, new_size);
  }
  return result;
}

static struct alloc_snapshot begin_phase(struct alloc_stats *stats) {
  struct alloc_snapshot result;
  stats->phase_peak_bytes = stats->live_bytes;
  result.allocations = stats->allocations;
  result.resizes = stats->resizes;
  result.requested_bytes = stats->requested_bytes;
  result.live_bytes = stats->live_bytes;
  return result;
}

static struct metric end_phase(const struct alloc_stats *stats, struct alloc_snapshot before, uint64_t elapsed_ns) {
  struct metric result;
  result.elapsed_ns = elapsed_ns;
  result.allocations = stats->allocations - before.allocations;
  result.resizes = stats->resizes - before.resizes;
  result.requested_bytes = stats->requested_bytes - before.requested_bytes;
  result.live_bytes = stats->live_bytes;
  result.peak_bytes = stats->phase_peak_bytes;
  return result;
}

static int run_sample(struct sample *sample) {
  struct alloc_stats stats = {0};
  struct alloc_snapshot before;
  uint64_t start;
  uint64_t first_chunk_elapsed = 0;

  memset(sample, 0, sizeof(*sample));

  before = begin_phase(&stats);
  start = now_ns();
  lua_State *L = lua_newstate(counting_alloc, &stats, 0);
  uint64_t elapsed = now_ns() - start;
  if (L == NULL) return 1;
  sample->phases[PHASE_NEWSTATE] = end_phase(&stats, before, elapsed);
  first_chunk_elapsed += elapsed;

  before = begin_phase(&stats);
  start = now_ns();
  luaL_openlibs(L);
  elapsed = now_ns() - start;
  sample->phases[PHASE_OPENLIBS] = end_phase(&stats, before, elapsed);
  first_chunk_elapsed += elapsed;

  sample->phases[PHASE_STARTUP_TOTAL].elapsed_ns = first_chunk_elapsed;
  sample->phases[PHASE_STARTUP_TOTAL].allocations = stats.allocations;
  sample->phases[PHASE_STARTUP_TOTAL].resizes = stats.resizes;
  sample->phases[PHASE_STARTUP_TOTAL].requested_bytes = stats.requested_bytes;
  sample->phases[PHASE_STARTUP_TOTAL].live_bytes = stats.live_bytes;
  sample->phases[PHASE_STARTUP_TOTAL].peak_bytes = stats.peak_bytes;

  before = begin_phase(&stats);
  start = now_ns();
  int status = luaL_loadstring(L, "");
  elapsed = now_ns() - start;
  if (status != LUA_OK) {
    fprintf(stderr, "C API startup benchmark load failed: %s\n", lua_tostring(L, -1));
    lua_close(L);
    return 1;
  }
  sample->phases[PHASE_LOAD] = end_phase(&stats, before, elapsed);
  first_chunk_elapsed += elapsed;

  before = begin_phase(&stats);
  start = now_ns();
  status = lua_pcall(L, 0, 0, 0);
  elapsed = now_ns() - start;
  if (status != LUA_OK) {
    fprintf(stderr, "C API startup benchmark call failed: %s\n", lua_tostring(L, -1));
    lua_close(L);
    return 1;
  }
  sample->phases[PHASE_CALL] = end_phase(&stats, before, elapsed);
  first_chunk_elapsed += elapsed;

  sample->phases[PHASE_FIRST_CHUNK].elapsed_ns = first_chunk_elapsed;
  sample->phases[PHASE_FIRST_CHUNK].allocations = stats.allocations;
  sample->phases[PHASE_FIRST_CHUNK].resizes = stats.resizes;
  sample->phases[PHASE_FIRST_CHUNK].requested_bytes = stats.requested_bytes;
  sample->phases[PHASE_FIRST_CHUNK].live_bytes = stats.live_bytes;
  sample->phases[PHASE_FIRST_CHUNK].peak_bytes = stats.peak_bytes;

  before = begin_phase(&stats);
  start = now_ns();
  lua_close(L);
  elapsed = now_ns() - start;
  sample->phases[PHASE_CLOSE] = end_phase(&stats, before, elapsed);
  if (stats.live_bytes != 0) {
    fprintf(stderr, "C API startup benchmark allocator leak: %llu bytes\n", (unsigned long long)stats.live_bytes);
    return 1;
  }
  return 0;
}

static int compare_u64(const void *lhs, const void *rhs) {
  uint64_t a = *(const uint64_t *)lhs;
  uint64_t b = *(const uint64_t *)rhs;
  return (a > b) - (a < b);
}

static uint64_t metric_field(const struct metric *metric, int field) {
  switch (field) {
    case 0: return metric->elapsed_ns;
    case 1: return metric->allocations;
    case 2: return metric->resizes;
    case 3: return metric->requested_bytes;
    case 4: return metric->live_bytes;
    case 5: return metric->peak_bytes;
    default: abort();
  }
}

static uint64_t percentile(const struct sample *samples, size_t count, int phase, int field, unsigned percent) {
  uint64_t *values = (uint64_t *)malloc(count * sizeof(*values));
  if (values == NULL) abort();
  for (size_t i = 0; i < count; i++) values[i] = metric_field(&samples[i].phases[phase], field);
  qsort(values, count, sizeof(*values), compare_u64);
  size_t rank = (percent * count + 99) / 100;
  if (rank == 0) rank = 1;
  uint64_t result = values[rank - 1];
  free(values);
  return result;
}

static size_t parse_size(const char *value, int allow_zero) {
  char *end = NULL;
  unsigned long long parsed = strtoull(value, &end, 10);
  if (value[0] == '\0' || *end != '\0' || (!allow_zero && parsed == 0) || parsed > SIZE_MAX) {
    fprintf(stderr, "invalid numeric option: %s\n", value);
    exit(2);
  }
  return (size_t)parsed;
}

int main(int argc, char **argv) {
  size_t iterations = 1000;
  size_t warmup = 100;
  const char *engine = "c-api";

  for (int i = 1; i < argc; i++) {
    const char *arg = argv[i];
    if (strcmp(arg, "--engine") == 0) {
      if (++i >= argc) return 2;
      engine = argv[i];
    } else if (strncmp(arg, "--engine=", 9) == 0) {
      engine = arg + 9;
    } else if (strcmp(arg, "--iterations") == 0) {
      if (++i >= argc) return 2;
      iterations = parse_size(argv[i], 0);
    } else if (strncmp(arg, "--iterations=", 13) == 0) {
      iterations = parse_size(arg + 13, 0);
    } else if (strcmp(arg, "--warmup") == 0) {
      if (++i >= argc) return 2;
      warmup = parse_size(argv[i], 1);
    } else if (strncmp(arg, "--warmup=", 9) == 0) {
      warmup = parse_size(arg + 9, 1);
    } else {
      fprintf(stderr, "unknown option: %s\n", arg);
      return 2;
    }
  }

  struct sample ignored;
  for (size_t i = 0; i < warmup; i++) if (run_sample(&ignored) != 0) return 1;

  struct sample *samples = (struct sample *)calloc(iterations, sizeof(*samples));
  if (samples == NULL) return 1;
  for (size_t i = 0; i < iterations; i++) {
    if (run_sample(&samples[i]) != 0) {
      free(samples);
      return 1;
    }
  }

  printf("%s startup (ReleaseFast), iterations=%zu, warmup=%zu\n", engine, iterations, warmup);
  printf("phase           median-ns      p95-ns  alloc  resize  requested-B    live-B    peak-B\n");
  for (int phase = 0; phase < PHASE_COUNT; phase++) {
    printf("%-13s %11llu %11llu %6llu %7llu %12llu %9llu %9llu\n",
      phase_names[phase],
      (unsigned long long)percentile(samples, iterations, phase, 0, 50),
      (unsigned long long)percentile(samples, iterations, phase, 0, 95),
      (unsigned long long)percentile(samples, iterations, phase, 1, 50),
      (unsigned long long)percentile(samples, iterations, phase, 2, 50),
      (unsigned long long)percentile(samples, iterations, phase, 3, 50),
      (unsigned long long)percentile(samples, iterations, phase, 4, 50),
      (unsigned long long)percentile(samples, iterations, phase, 5, 50));
  }
  putchar('\n');
  free(samples);
  return 0;
}
