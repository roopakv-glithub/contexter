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

The app signs users in with Supabase Auth. Enable email/password sign-up and
configure email confirmation in the Supabase dashboard. After confirming an
account, return to the Windows app and sign in. Authenticated Edge Functions
call NVIDIA; the NVIDIA key is stored only as a Supabase function secret, never
in the Windows app or repository.

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
deploying; never paste the key into source code or command history.

The migration creates per-user `analysis_reports` and `prompt_history` tables
with row-level security. Only the public Supabase client key is used by the
desktop app; never put a Supabase `service_role` key in the app, repository, or
GitHub Actions. Rotate any provider or service-role keys that have been posted
or otherwise exposed. The Edge Functions use a five-request-per-minute,
per-account AI limit.

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
repository analysis use authenticated Supabase Edge Functions instead.

## GitHub Actions

`.github/workflows/windows.yml` runs Flutter analysis and widget tests, builds
the Windows release, and uploads the release folder as a downloadable artifact
for pushes, pull requests, and manual workflow runs. Push a version tag such as
`v1.0.0` to create a GitHub Release containing `moscowt.exe` and a ZIP with the
complete Windows application bundle. Run the released app from the extracted
ZIP so its Flutter runtime and data files are alongside the executable.
