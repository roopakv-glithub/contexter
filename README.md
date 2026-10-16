# Moscowt

Moscowt is a Flutter desktop app for Windows that uses NVIDIA's OpenAI-compatible
`z-ai/glm-5.3` API to analyze projects and enhance developer prompts. Its UI
includes project setup, mascot/agent selection, an AI prompt workspace,
repository analysis, saved report and prompt history, and settings.

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

## Supabase and NVIDIA setup

The app opens directly without sign-in. Project reports and enhanced prompt
history are stored locally on the device. Supabase Edge Functions call NVIDIA;
the NVIDIA key is stored only as a Supabase function secret, never in the
Windows app or repository.

In the Supabase dashboard, add `NVIDIA_API_KEY` under **Edge Function
Secrets**. Then, with the Supabase CLI installed and authenticated:

```powershell
supabase login
supabase link --project-ref pkccuhjqxgqpyrtiykse
supabase db push
supabase functions deploy analyze-project
supabase functions deploy enhance-prompt
```

Set `NVIDIA_API_KEY` to a newly rotated provider key in the dashboard before
deploying; never paste the key into source code or command history. Apply the
database migrations before deploying the functions. The AI functions use a
five-request-per-minute limit per client IP and require the standard
`SUPABASE_SERVICE_ROLE_KEY` function secret for the server-side limiter.

Only the public Supabase client key is used by the desktop app; never put a
Supabase `service_role` key in the app, repository, or GitHub Actions. Rotate
any provider or service-role keys that have been posted or otherwise exposed.

Public GitHub URLs and locally selected folders are supported. Private GitHub
repositories require a secure GitHub integration and are not fetched using a
personal token. Local scanning excludes build/generated folders, environment
files, and common secret patterns before uploading source to the analysis
function. To keep analysis responsive and requests bounded, each run sends at
most 180 supported source/manifest files and 900,000 characters; the report
shows files that were skipped or truncated.

## Flutter and C++

The interface and application flow are written in Flutter/Dart. The Windows
runner includes a native C++ prompt formatter; AI-powered enhancement and
repository analysis use Supabase Edge Functions.

## GitHub Actions

`.github/workflows/windows.yml` runs Flutter analysis and widget tests, builds
the Windows release, and uploads the release folder as a downloadable artifact
for pushes, pull requests, and manual workflow runs. Push a version tag such as
`v1.0.0` to create a GitHub Release containing `moscowt.exe` and a ZIP with the
complete Windows application bundle. Run the released app from the extracted
ZIP so its Flutter runtime and data files are alongside the executable.
