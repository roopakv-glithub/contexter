#include "prompt_engine.h"

#include <sstream>

std::string EnhancePrompt(const std::string& prompt) {
  std::istringstream input(prompt);
  std::ostringstream output;
  std::string line;
  bool first = true;

  output << "Task:\n";
  while (std::getline(input, line)) {
    if (!first) {
      output << '\n';
    }
    output << line;
    first = false;
  }
  output << "\n\nConstraints:\n"
         << "- Inspect the existing project and reuse established patterns.\n"
         << "- Keep changes focused; avoid unnecessary dependencies.\n"
         << "- Preserve current behavior and report any assumptions.\n\n"
         << "Expected output:\n"
         << "- Implement the requested change.\n"
         << "- Summarize the files changed and how the result was verified.\n\n"
         << "Acceptance criteria:\n"
         << "- The requested behavior works without regressing existing functionality.\n"
         << "- Relevant tests pass, or any testing limitations are explained.";
  return output.str();
}
