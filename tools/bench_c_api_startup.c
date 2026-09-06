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

#define PHASE_COUNT 8

enum phase {
  PHASE_NEWSTATE,
  PHASE_OPENLIBS,
  PHASE_REGISTER,
  PHASE_STARTUP_TOTAL,
  PHASE_LOAD,
  PHASE_CALL,
  PHASE_CLOSE,
  PHASE_FIRST_CHUNK,
};

static const char *phase_names[PHASE_COUNT] = {
  "newstate", "openlibs", "register-3", "startup-total", "load", "call", "close", "first-chunk",
};

static const char *host_chunk = "return host_tag(host_add(host_double(20), 2))";

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

static int host_add(lua_State *L) {
  lua_Integer lhs = luaL_checkinteger(L, 1);
  lua_Integer rhs = luaL_checkinteger(L, 2);
  lua_pushinteger(L, lhs + rhs);
  return 1;
}

static int host_double(lua_State *L) {
  lua_pushinteger(L, luaL_checkinteger(L, 1) * 2);
  return 1;
}

static int host_tag(lua_State *L) {
  lua_pushinteger(L, luaL_checkinteger(L, 1));
  lua_pushliteral(L, "host-ok");
  return 2;
}

static int run_sample(struct sample *sample, int host) {
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
  if (host) {
    luaL_requiref(L, LUA_GNAME, luaopen_base, 1);
    lua_pop(L, 1);
  } else {
    luaL_openlibs(L);
  }
  elapsed = now_ns() - start;
  sample->phases[PHASE_OPENLIBS] = end_phase(&stats, before, elapsed);
  first_chunk_elapsed += elapsed;

  if (host) {
    before = begin_phase(&stats);
    start = now_ns();
    lua_register(L, "host_add", host_add);
    lua_register(L, "host_double", host_double);
    lua_register(L, "host_tag", host_tag);
    elapsed = now_ns() - start;
    sample->phases[PHASE_REGISTER] = end_phase(&stats, before, elapsed);
    first_chunk_elapsed += elapsed;
  }

  sample->phases[PHASE_STARTUP_TOTAL].elapsed_ns = first_chunk_elapsed;
  sample->phases[PHASE_STARTUP_TOTAL].allocations = stats.allocations;
  sample->phases[PHASE_STARTUP_TOTAL].resizes = stats.resizes;
  sample->phases[PHASE_STARTUP_TOTAL].requested_bytes = stats.requested_bytes;
  sample->phases[PHASE_STARTUP_TOTAL].live_bytes = stats.live_bytes;
  sample->phases[PHASE_STARTUP_TOTAL].peak_bytes = stats.peak_bytes;

  before = begin_phase(&stats);
  start = now_ns();
  int status = luaL_loadstring(L, host ? host_chunk : "");
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
  status = lua_pcall(L, 0, host ? 2 : 0, 0);
  elapsed = now_ns() - start;
  if (status != LUA_OK) {
    fprintf(stderr, "C API startup benchmark call failed: %s\n", lua_tostring(L, -1));
    lua_close(L);
    return 1;
  }
  sample->phases[PHASE_CALL] = end_phase(&stats, before, elapsed);
  first_chunk_elapsed += elapsed;

  if (host && (!lua_isinteger(L, -2) || lua_tointeger(L, -2) != 42 ||
      lua_type(L, -1) != LUA_TSTRING || strcmp(lua_tostring(L, -1), "host-ok") != 0)) {
    fprintf(stderr, "C API host benchmark returned unexpected results\n");
    lua_close(L);
    return 1;
  }

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


/* Internal worker protocol: iterations warmup host. The Zig runner owns the CLI
 * and reporting. Emit all raw samples after measurement, outside the timers. */
static int parse_count(const char *text, size_t *value) {
  if (*text == '\0') return 1;
  size_t result = 0;
  for (const char *p = text; *p; p++) {
    if (*p < '0' || *p > '9' || result > (SIZE_MAX - (size_t)(*p - '0')) / 10) return 1;
    result = result * 10 + (size_t)(*p - '0');
  }
  *value = result;
  return 0;
}

int main(int argc, char **argv) {
  size_t iterations, warmup, host;
  if (argc != 4 || parse_count(argv[1], &iterations) || iterations == 0 ||
      parse_count(argv[2], &warmup) || parse_count(argv[3], &host) || host > 1) return 2;
  struct sample *samples = calloc(iterations, sizeof(*samples));
  if (samples == NULL) return 1;
  struct sample ignored;
  for (size_t i = 0; i < warmup; i++) {
    if (run_sample(&ignored, (int)host)) { free(samples); return 1; }
  }
  for (size_t i = 0; i < iterations; i++) {
    if (run_sample(&samples[i], (int)host)) { free(samples); return 1; }
  }
  printf("{\"protocol_version\":1,\"samples\":[");
  for (size_t i = 0; i < iterations; i++) {
    if (i) putchar(',');
    printf("{\"phases\":{");
    for (int phase = 0; phase < PHASE_COUNT; phase++) {
      const struct metric *m = &samples[i].phases[phase];
      if (phase) putchar(',');
      printf("\"%s\":{\"elapsed_ns\":%llu,\"allocations\":%llu,\"resizes\":%llu,"
        "\"requested_bytes\":%llu,\"live_bytes\":%llu,\"peak_bytes\":%llu}",
        phase_names[phase], (unsigned long long)m->elapsed_ns, (unsigned long long)m->allocations,
        (unsigned long long)m->resizes, (unsigned long long)m->requested_bytes,
        (unsigned long long)m->live_bytes, (unsigned long long)m->peak_bytes);
    }
    printf("}}");
  }
  printf("]}\n");
  free(samples);
  return ferror(stdout) ? 1 : 0;
}
