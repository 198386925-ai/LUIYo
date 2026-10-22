// In-process bridge to the vendored zsign engine.
//
// zsign ships as a command-line tool whose whole flow lives in
// src/zsign.cpp's main(). Rather than forking a process (impossible
// in the iOS sandbox), the translation unit is included here with
// main() renamed, and the bridge drives it with a fabricated argv —
// the same integration other iOS signers use for this engine.
//
// The engine logs through raw write() calls to stdout (ZLog) and
// OpenSSL reports to stderr, so both descriptors are redirected to
// a log file for the duration of the call: on failure the tail of
// that log is handed back to the caller as the error text.

#include "luiyo_zsign.h"

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include <fcntl.h>
#include <unistd.h>

#define main luiyo_zsign_engine_main
#include "../zsign-src/zsign.cpp"
#undef main

extern "C" int luiyo_zsign_sign(const char* ipaPath,
                                const char* p12Path,
                                const char* password,
                                const char* profilePath,
                                const char* outputPath,
                                const char* tempDir,
                                char* errorBuffer,
                                int errorBufferSize) {
    if (errorBuffer != NULL && errorBufferSize > 0) {
        errorBuffer[0] = '\0';
    }

    // --- Redirect stdout/stderr to a log file -------------------
    std::string logPath = std::string(tempDir) + "/zsign-engine.log";
    int logFd = open(logPath.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
    int savedOut = -1, savedErr = -1;
    if (logFd >= 0) {
        fflush(stdout);
        fflush(stderr);
        savedOut = dup(STDOUT_FILENO);
        savedErr = dup(STDERR_FILENO);
        dup2(logFd, STDOUT_FILENO);
        dup2(logFd, STDERR_FILENO);
    }

    // --- Fabricated argv ----------------------------------------
    // zsign -f -k <p12> -p <password> -m <profile> -t <tempDir>
    //       -o <output> <input.ipa>
    std::vector<std::string> args = {
        "zsign",
        "-f",
        "-k", p12Path,
        "-p", password,
        "-m", profilePath,
        "-t", tempDir,
        "-o", outputPath,
        ipaPath,
    };
    std::vector<char*> argv;
    argv.reserve(args.size() + 1);
    for (auto& arg : args) {
        argv.push_back(const_cast<char*>(arg.c_str()));
    }
    argv.push_back(NULL);

    // getopt keeps global state between calls; optind == 0 makes
    // the BSD implementation reinitialise on the next call.
    optind = 0;
    int rc = luiyo_zsign_engine_main((int)args.size(), argv.data());

    // --- Restore descriptors ------------------------------------
    if (logFd >= 0) {
        fflush(stdout);
        fflush(stderr);
        if (savedOut >= 0) { dup2(savedOut, STDOUT_FILENO); close(savedOut); }
        if (savedErr >= 0) { dup2(savedErr, STDERR_FILENO); close(savedErr); }
        close(logFd);
    }

    // --- Success also requires the output file to exist ---------
    if (0 == rc && 0 != access(outputPath, F_OK)) {
        rc = 1;
    }

    // --- On failure, surface the engine's own log tail ----------
    if (0 != rc && errorBuffer != NULL && errorBufferSize > 1) {
        FILE* log = fopen(logPath.c_str(), "rb");
        if (log != NULL) {
            fseek(log, 0, SEEK_END);
            long size = ftell(log);
            long keep = size < (errorBufferSize - 1) ? size : (errorBufferSize - 1);
            fseek(log, size - keep, SEEK_SET);
            size_t read = fread(errorBuffer, 1, (size_t)keep, log);
            errorBuffer[read] = '\0';
            fclose(log);
            // Trim leading partial line for readability.
            char* firstNewline = strchr(errorBuffer, '\n');
            if (firstNewline != NULL && firstNewline != errorBuffer && keep == errorBufferSize - 1) {
                memmove(errorBuffer, firstNewline + 1, strlen(firstNewline + 1) + 1);
            }
        }
        if (errorBuffer[0] == '\0') {
            snprintf(errorBuffer, (size_t)errorBufferSize, "zsign exited with code %d", rc);
        }
    }
    return rc;
}
