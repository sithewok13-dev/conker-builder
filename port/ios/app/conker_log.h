#pragma once

namespace conker {
    // Appends a line to Documents/conker-log.txt (visible in the Files app under
    // "Conker") and to the system log. Each line is flushed to disk right away,
    // so after a crash the last line shows the step that was running.
    void log(const char *format, ...) __attribute__((format(printf, 1, 2)));
}
