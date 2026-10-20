/**
 * ContextForge — Repo to Markdown Integration Script
 * Interacts with repo-to-markdown.com conversion workflow or runs the standard
 * Repo-to-Markdown specification to convert a GitHub repository into an AI-ready Markdown document.
 */

const https = require('https');
const fs = require('fs');
const path = require('path');

function parseRepositoryInput(repoUrlString) {
  let owner, repo, branch = null, subdirectory = '';
  const normalizeSubdirectory = (p) => (p ? p.replace(/^\/+|\/+$/g, '') : '');

  if (repoUrlString.includes('github.com')) {
    const url = new URL(repoUrlString);
    const parts = url.pathname.split('/').filter(Boolean);
    if (parts.length < 2) {
      throw new Error('Invalid GitHub URL format. Provide owner/repo or full repository URL.');
    }
    owner = parts[0];
    repo = parts[1].replace(/\.git$/, '');

    if (parts.length > 2) {
      const routeType = parts[2];
      if ((routeType === 'tree' || routeType === 'blob') && parts.length > 3) {
        branch = parts[3];
        if (parts.length > 4) {
          subdirectory = normalizeSubdirectory(parts.slice(4).join('/'));
        }
      } else if (routeType === 'raw' && parts.length > 3) {
        branch = parts[3];
        subdirectory = normalizeSubdirectory(parts.slice(4).join('/'));
      } else {
        const special = new Set(['issues', 'pulls', 'pull', 'actions', 'commits', 'releases']);
        if (!special.has(routeType)) {
          subdirectory = normalizeSubdirectory(parts.slice(2).join('/'));
        }
      }
    }
  } else {
    const parts = repoUrlString.split('/');
    if (parts.length !== 2) {
      throw new Error('Invalid repository format. Please use "owner/repository".');
    }
    owner = parts[0];
    repo = parts[1];
  }

  return { owner, repo, branch, subdirectory, originalUrl: repoUrlString };
}

function fetchJson(url, headers = {}) {
  return new Promise((resolve, reject) => {
    const options = {
      headers: {
        'User-Agent': 'ContextForge-RepoToMarkdown/1.0',
        Accept: 'application/vnd.github.v3+json',
        ...headers,
      },
    };
    https.get(url, options, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try {
            resolve(JSON.parse(data));
          } catch (e) {
            reject(new Error(`Failed to parse response: ${e.message}`));
          }
        } else {
          reject(new Error(`HTTP ${res.statusCode}: ${data.slice(0, 200)}`));
        }
      });
    }).on('error', reject);
  });
}

function fetchText(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': 'ContextForge-RepoToMarkdown/1.0' } }, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve(data);
        } else {
          reject(new Error(`HTTP ${res.statusCode}`));
        }
      });
    }).on('error', reject);
  });
}

const skipPatterns = [
  'node_modules/', '.git/', '*.min.js', '*.min.css', '*.map',
  'package-lock.json', 'yarn.lock', 'pnpm-lock.yaml', 'composer.lock',
  'Gemfile.lock', 'Pipfile.lock', 'poetry.lock', 'Cargo.lock', 'go.sum',
  'mix.lock', 'pubspec.lock', '*.test.js', '*.spec.js', '*.test.ts',
  '*.spec.ts', '__tests__/', 'test/', 'tests/', '.gitignore', '.gitattributes',
  '.editorconfig', '.prettierrc*', '.eslintrc*', '*.config.js', '*.config.ts',
  '*.config.json', '.env*', '.env.local', '.env.production', '.env.development',
  '.env.test', '.envrc', '.nvmrc', '.node-version', '.ruby-version',
  '.python-version', '.tool-versions', 'tsconfig.json', 'babel.config.js',
  'webpack.config.js', 'vite.config.js', 'jest.config.js', '*.md',
  '*.bundle.js', '*.chunk.js', '*.pyc', '*.pyo', '__pycache__/', '*.egg-info/',
  '*.whl', '.tox/', 'venv/', 'env/', '.pytest_cache/', 'dist/', 'build/',
  'out/', 'target/', 'bin/', '.vscode/', '.idea/',
];

const binaryExtensions = new Set([
  '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.ico', '.svg', '.pdf',
  '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.zip', '.rar',
  '.7z', '.tar', '.gz', '.exe', '.dll', '.so', '.dylib', '.bin',
  '.dat', '.db', '.sqlite', '.mp3', '.mp4', '.avi', '.mov', '.wav',
  '.flac', '.ttf', '.otf', '.woff', '.woff2', '.eot',
]);

function matchesGlob(filename, pattern) {
  const regexPattern = pattern
    .replace(/\./g, '\\.')
    .replace(/\*/g, '.*')
    .replace(/\?/g, '.')
    .replace(/\//g, '\\/');
  const regex = new RegExp('^' + regexPattern + '$', 'i');
  return regex.test(filename) || filename.includes(pattern.toLowerCase());
}

function shouldSkipFile(file) {
  const filename = file.path.toLowerCase();
  const basename = filename.split('/').pop();
  if (file.size && file.size > 1024 * 1024) return true;

  const dot = filename.lastIndexOf('.');
  if (dot >= 0 && binaryExtensions.has(filename.slice(dot))) return true;

  for (const pattern of skipPatterns) {
    if (matchesGlob(filename, pattern) || matchesGlob(basename, pattern)) {
      return true;
    }
  }
  return false;
}

function removeLicenseHeaders(content) {
  const lines = content.split('\n');
  let startIndex = 0;
  const licenseKeywords = ['license', 'copyright', 'mit', 'apache', 'gpl', 'bsd'];

  for (let i = 0; i < Math.min(20, lines.length); i++) {
    const line = lines[i].toLowerCase();
    if (licenseKeywords.some((k) => line.includes(k))) {
      if (line.includes('*/') || line.includes('-->')) {
        startIndex = i + 1;
        break;
      }
      if (line.startsWith('//') || line.startsWith('#')) {
        startIndex = i + 1;
        break;
      }
    }
    if (
      line.trim() &&
      !line.trim().startsWith('//') &&
      !line.trim().startsWith('#') &&
      !line.trim().startsWith('/*') &&
      !line.trim().startsWith('*') &&
      !line.trim().startsWith('<!--')
    ) {
      break;
    }
  }
  if (startIndex > 0) {
    return lines.slice(startIndex).join('\n').replace(/^\s*\n+/, '');
  }
  return content;
}

function redactSecrets(content) {
  return content
    .replace(/-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g, '[REDACTED PRIVATE KEY]')
    .replace(/\b(?:nvapi-[A-Za-z0-9_-]{16,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,}|AKIA[A-Z0-9]{16}|AIza[A-Za-z0-9_-]{30,}|xox[baprs]-[A-Za-z0-9-]{20,})\b/g, '[REDACTED TOKEN]')
    .replace(/\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\b/g, '[REDACTED JWT]')
    .replace(/((?:api[_-]?key|(?:access|auth)[_-]?token|token|secret|password|credential|client[_-]?secret|service[_-]?role|private[_-]?key)\s*[:=]\s*["']?)[^"'`\s,;]+/gi, '$1[REDACTED]');
}

function generateDirectoryTree(files, subdirectory = '') {
  const tree = {};
  files.forEach((file) => {
    let currentPath = file.path;
    if (subdirectory && currentPath.startsWith(subdirectory + '/')) {
      currentPath = currentPath.substring(subdirectory.length + 1);
    }
    const parts = currentPath.split('/');
    let current = tree;
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
      if (!current[part]) {
        current[part] = i === parts.length - 1 ? null : {};
      }
      current = current[part];
    }
  });

  function treeToString(node, prefix = '', isLast = true) {
    let result = '';
    const entries = Object.entries(node).sort(([a, valA], [b, valB]) => {
      const aIsDir = valA !== null;
      const bIsDir = valB !== null;
      if (aIsDir !== bIsDir) return bIsDir - aIsDir;
      return a.localeCompare(b);
    });

    entries.forEach(([name, value], index) => {
      const last = index === entries.length - 1;
      const connector = last ? '└── ' : '├── ';
      result += prefix + connector + name + '\n';
      if (value !== null) {
        result += treeToString(value, prefix + (last ? '    ' : '│   '), last);
      }
    });
    return result;
  }

  return treeToString(tree);
}

async function convert(repoUrlString) {
  const repoInfo = parseRepositoryInput(repoUrlString);
  const { owner, repo, branch, subdirectory } = repoInfo;

  const branchesToTry = branch ? [branch, 'main', 'master', 'dev'] : ['main', 'master', 'dev'];
  let workingBranch = null;
  let allTreeFiles = [];

  const token = process.env.GITHUB_PAT || process.env.GITHUB_TOKEN;
  const headers = token ? { Authorization: `token ${token}` } : {};

  for (const b of branchesToTry) {
    try {
      const apiUrl = `https://api.github.com/repos/${owner}/${repo}/git/trees/${b}?recursive=1`;
      const data = await fetchJson(apiUrl, headers);
      if (data && Array.isArray(data.tree) && data.tree.length > 0) {
        workingBranch = b;
        allTreeFiles = data.tree.filter((i) => i.type === 'blob');
        break;
      }
    } catch (_) {
      continue;
    }
  }

  if (!workingBranch) {
    throw new Error(`Could not access repository "${owner}/${repo}". Check that it is public.`);
  }

  let filesList = allTreeFiles;
  if (subdirectory) {
    filesList = allTreeFiles.filter((f) => f.path.startsWith(subdirectory + '/'));
  }

  const filesToProcess = filesList.filter((f) => !shouldSkipFile(f));
  if (filesToProcess.length === 0) {
    throw new Error(`No non-binary source files found in repository "${owner}/${repo}" after applying Repo-to-Markdown filters.`);
  }

  const repositoryPath = subdirectory ? `${owner}/${repo}/${subdirectory}` : `${owner}/${repo}`;
  const directoryTree = generateDirectoryTree(filesToProcess, subdirectory);

  let output = `This document contains the complete source code of the repository consolidated into a single file for streamlined AI analysis.
The repository contents have been processed and combined with security validation bypassed.

# Repository Overview

## About This Document
This consolidated file represents the complete codebase from the repository, 
merged into a unified document optimized for AI consumption and automated 
analysis workflows.

## Repository Information
- **Repository:** ${repositoryPath}
- **Branch:** ${workingBranch}
- **Total Files:** ${filesToProcess.length}
- **Generated:** ${new Date().toISOString()}

# Repository Structure

\`\`\`
${repositoryPath}/
${directoryTree}\`\`\`

`;

  for (const file of filesToProcess) {
    try {
      const rawUrl = `https://raw.githubusercontent.com/${owner}/${repo}/${workingBranch}/${file.path}`;
      const rawContent = await fetchText(rawUrl);
      const cleanContent = redactSecrets(removeLicenseHeaders(rawContent));

      output += `================================================================================\n`;
      output += `// File: ${file.path}\n`;
      output += `================================================================================\n`;
      output += cleanContent;
      if (!cleanContent.endsWith('\n')) output += '\n';
      output += '\n';
    } catch (e) {
      // Skip file if download fails
    }
  }

  return output;
}

async function main() {
  const repoUrl = process.argv[2];
  const outputFile = process.argv[3];
  if (!repoUrl) {
    console.error('Usage: node repo_to_markdown.js <github_repo_url> [output_file]');
    process.exit(1);
  }

  try {
    const markdown = await convert(repoUrl);
    if (outputFile) {
      fs.writeFileSync(outputFile, markdown, 'utf8');
      console.log(`Successfully converted ${repoUrl} to ${outputFile}`);
    } else {
      process.stdout.write(markdown);
    }
  } catch (err) {
    console.error(`Error: ${err.message}`);
    process.exit(1);
  }
}

if (require.main === module) {
  main();
}

module.exports = { convert, parseRepositoryInput };
