/* PS5 support for the SuperTuxKart build: a heap that fits a game, and a log
 * that can be read back off the console.
 *
 * A native title has nowhere for stderr to go, so the first thing this does is
 * point stdout and stderr at a file in the title folder. Without that, a crash
 * before the first frame tells you nothing at all, which is exactly the
 * situation this port is in.
 *
 * The heap comes from the PS5 OpenGL SDK's allocator (native-app/app_heap.c):
 * it owns malloc for the whole executable and takes its memory from direct
 * memory once more than 128 MiB is asked for. SuperTuxKart loads tracks,
 * karts and textures that the 128 MiB default cannot hold, hence the size
 * below.
 */
#include <stdio.h>
#include <sys/types.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/* The SDK allocator reads this at startup. 1 GiB leaves room for the asset
   tree while staying well under what the console hands out; the allocator
   halves its request until a mapping succeeds, so asking high is safe. */
const size_t ps5_opengl_heap_size = 1024u * 1024u * 1024u;

/* Zero-filled allocations were on while the port was being brought up, so
   that reading memory nobody wrote behaved the same on every run. They cost
   a memset on every allocation, which shows when a track loads its textures,
   so they are off now that the game runs. calloc still returns zeroes. */
const int ps5_opengl_heap_zero_fill = 0;

/* Set once the log file is open, so the markers below know they will be
   seen. The game has hundreds of static objects and any one of them can be
   what stops the process, so each stage says so before it runs. */
int ps5_log_ready = 0;

/* The folders a title can turn up in; the log goes next to the game. */
static const char* const LOG_DIRS[] = {
	"/app0",
	"/system_ex/app/PPSA69421",
	"/mnt/sandbox/PPSA69421_000/app0",
};

__attribute__((constructor(101)))
static void ps5_open_log(void)
{
	char path[256];
	for (size_t i = 0; i < sizeof(LOG_DIRS) / sizeof(LOG_DIRS[0]); i++) {
		struct stat info;
		snprintf(path, sizeof(path), "%s/eboot.bin", LOG_DIRS[i]);
		if (stat(path, &info) != 0) continue;

		snprintf(path, sizeof(path), "%s/stk.log", LOG_DIRS[i]);
		if (!freopen(path, "w", stderr)) continue;
		/* Buffered: every unbuffered line became its own small writes to the
		   title folder, which is slow there. The buffer is flushed with every
		   frame-rate report and by the crash handlers in ps5-posix.c, so the
		   lines that say where a crash happened still reach the file. */
		static char log_buffer[64 * 1024];
		setvbuf(stderr, log_buffer, _IOFBF, sizeof(log_buffer));
		stdout = stderr;
		/* The system C library's printf ignores the stdout variable and
		   writes to descriptor 1 directly, which in a title goes to the
		   console's own output. The OpenGL SDK prints a profiling report
		   there every 10,000 draws, and the game froze for 3.5 s at exactly
		   that rhythm. Descriptors 1 and 2 now point at this file too. */
		if (fileno(stderr) != 1) dup2(fileno(stderr), 1);
		if (fileno(stderr) != 2) dup2(fileno(stderr), 2);
		fprintf(stderr, "stk: log opened at %s\n", path);
		fprintf(stderr, "stk: heap %zu MiB, zero fill %d\n",
		        ps5_opengl_heap_size / (1024u * 1024u), ps5_opengl_heap_zero_fill);
		ps5_log_ready = 1;
		return;
	}
}

/* Runs after every other constructor at this priority level: reaching this
   means the static initialisers of the game and its libraries all completed. */
__attribute__((destructor(101)))
static void ps5_note_exit(void)
{
	if (ps5_log_ready) fprintf(stderr, "stk: process is shutting down\n");
}

__attribute__((constructor(65535)))
static void ps5_note_constructors_done(void)
{
	if (ps5_log_ready) fprintf(stderr, "stk: static constructors finished\n");
}

/* Direct memory, reported with the frame rate: the size the title was given
   and the largest block still free. A largest block rather than a total,
   because that is what the kernel reports; a falling figure still shows the
   memory filling up. */
int sceKernelAvailableDirectMemorySize(off_t start, off_t end, size_t alignment,
                                       off_t* start_out, size_t* size_out);
size_t sceKernelGetDirectMemorySize(void);

unsigned ps5_printed_lines(void);   /* ps5-posix.c */

void ps5_log_memory(void)
{
	const size_t total = sceKernelGetDirectMemorySize();
	off_t where = 0;
	size_t largest = 0;
	if (sceKernelAvailableDirectMemorySize(0, (off_t)total, 64 * 1024,
	                                      &where, &largest) != 0)
		largest = 0;
	static unsigned previous_lines;
	const unsigned lines = ps5_printed_lines();
	fprintf(stderr, "stk: direct memory %zu MiB, largest free block %zu MiB, "
	        "%u lines printed by the libraries since the last report\n",
	        total / (1024u * 1024u), largest / (1024u * 1024u),
	        lines - previous_lines);
	previous_lines = lines;
	fflush(stderr);
}
