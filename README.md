# Moscowt

Moscowt is a Flutter desktop app for Windows that turns rough developer requests
into structured prompts. Its desktop UI follows the supplied Moscowt design:
project setup, mascot/agent selection, a prompt workspace, repository context,
history, and settings.

## Run on Windows

Install Flutter with Windows desktop support and Visual Studio's **Desktop
development with C++** workload. Then run:

```powershell
flutter pub get
flutter run -d windows
```

Build a distributable Windows application:

```powershell
flutter build windows --release
```

The app output is in `build\windows\x64\runner\Release`.

## Flutter and C++

The interface and application flow are written in Flutter/Dart. The Windows
runner exposes the `moscowt/native` method channel and calls the C++ prompt
formatter in `windows/runner/prompt_engine.cpp`. This first native engine
structures a request locally; model-powered enhancement, GitHub authentication,
and real repository indexing still need provider credentials and their
respective integrations. Never commit access tokens or API keys.

## GitHub Actions

`.github/workflows/windows.yml` runs Flutter analysis and widget tests, builds
the Windows release, and uploads the release folder as a downloadable artifact
for pushes, pull requests, and manual workflow runs.
