<div align="center">

<img src="https://raw.githubusercontent.com/elfenomenokim/notion-mcp-shared/main/docs/logo.svg" width="96" height="96" alt="하나의 서비스가 여러 클라이언트를 처리하는 모습을 나타낸 아이콘">

# notion-mcp-shared
[English](README.md)

로컬 HTTP 서비스 하나가 여러 AI 클라이언트의 Notion MCP 요청을 처리합니다.

Node.js · Python 3

[![license](https://img.shields.io/github/license/elfenomenokim/notion-mcp-shared)](https://github.com/elfenomenokim/notion-mcp-shared/blob/main/LICENSE)

stdio 클라이언트 5개가 452.17MiB를 쓰고, 같은 5개 세션이 공유 프로세스 하나에서 84.64MiB로 끝납니다. 저장된 Linux 측정에서 가져왔습니다.

[설치](#설치) · [구조](#구조) · [클라이언트 설정](#클라이언트-설정)

</div>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/elfenomenokim/notion-mcp-shared/main/docs/diagrams/notion-mcp-shared.ko.dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/elfenomenokim/notion-mcp-shared/main/docs/diagrams/notion-mcp-shared.ko.svg">
  <img src="https://raw.githubusercontent.com/elfenomenokim/notion-mcp-shared/main/docs/diagrams/notion-mcp-shared.ko.svg" alt="여러 클라이언트가 하나의 로컬 Notion MCP 서버로 요청을 보냅니다">
</picture>

## 설치

Node.js, npm, Python 3, curl, tar와 Notion integration token이 필요합니다.

```sh
./install.sh --secret
./install.sh
```

첫 명령은 서비스 bearer token을 권한 600인 로컬 파일에 저장합니다. 각 클라이언트 프로세스에 `NOTION_TOKEN`을 설정하세요. 서비스는 요청마다 그 값을 전달합니다. 기본 주소는 `http://127.0.0.1:58983/mcp`입니다.

macOS에서는 LaunchAgent, Linux에서는 `systemd --user`로 실행합니다. Linux 설치는 Ubuntu에서 실행해 봤습니다. 기존 macOS LaunchAgent는 따로 유지되며 공개 설치 스크립트를 macOS에서 직접 실행하지는 않았습니다.

## 구조

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/elfenomenokim/notion-mcp-shared/main/docs/diagrams/notion-mcp-shared.ko.dark.svg">
  <img src="https://raw.githubusercontent.com/elfenomenokim/notion-mcp-shared/main/docs/diagrams/notion-mcp-shared.ko.svg" alt="클라이언트 요청이 로컬 공유 서비스 하나를 거쳐 Notion API로 전달됩니다">
</picture>

`Authorization: Bearer`는 로컬 서비스에 접속할 때 사용합니다. `Notion-Token` 헤더는 요청별 Notion 계정을 고릅니다. 서비스 프로세스는 계정 token을 보관하지 않습니다.

## 클라이언트 설정

`clients/`에서 Claude Code, Codex, Pi, Antigravity, Kimi Code에 맞는 예제를 복사하세요. 클라이언트 프로세스가 bearer token과 `NOTION_TOKEN`을 읽을 수 있어야 합니다.

## 측정값

Ubuntu Linux에서 Node.js v22.23.5로 측정했습니다. 각 stdio 프로세스가 MCP `initialize`와 `tools/list`를 끝냈습니다. 공유 서비스는 같은 요청을 HTTP 클라이언트 5개가 동시에 보냈을 때 처리했습니다. 각 응답은 도구 24개를 반환했습니다. RSS는 실행 중과 완료 후 1초 동안 샘플링한 피크입니다.

| stdio MCP 프로세스 | stdio 전체 RSS | HTTP 세션 5개의 공유 서비스 RSS |
|---:|---:|---:|
| 1개 | 90.50 MiB | 84.64 MiB |
| 3개 | 271.04 MiB | 84.64 MiB |
| 5개 | 452.17 MiB | 84.64 MiB |

공유 서비스는 매 행에서 Node 프로세스 하나를 사용했습니다. 측정 자료는 [`docs/bench/linux-2026-11-17.json`](docs/bench/linux-2026-11-17.json)에 있습니다.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/elfenomenokim/notion-mcp-shared/main/docs/diagrams/notion-mcp-shared-rss.ko.dark.svg">
  <img src="https://raw.githubusercontent.com/elfenomenokim/notion-mcp-shared/main/docs/diagrams/notion-mcp-shared-rss.ko.svg" alt="Linux에서 측정한 피크 RSS 비교: stdio 1, 3, 5개는 90.50, 271.04, 452.17 MiB이며 HTTP 5개 세션을 처리한 공유 서버는 84.64 MiB입니다">
</picture>

설치 후 측정할 때 실행한 명령입니다.

```sh
server_pid=$(systemctl --user show notion-mcp-shared.service -p MainPID --value)
NOTION_TOKEN=benchmark-no-api-call python3 docs/bench/measure.py \
  --node "$(command -v node)" \
  --runtime "$HOME/.local/share/notion-mcp-shared/runtime/bin/cli.mjs" \
  --endpoint http://127.0.0.1:58983/mcp \
  --server-secret "$HOME/.secrets/notion-mcp-shared.env" \
  --server-pid "$server_pid" --counts 1 3 5 \
  --output docs/bench/linux-2026-11-17.json
```

측정 명령은 가짜 Notion token을 사용하며 Notion API를 호출하지 않습니다. 별도로 테스트 서비스에서 읽기 전용 `API-post-search` 요청 한 건이 성공했습니다. 이후 테스트 서비스와 임시 파일을 모두 지웠습니다.

## Upstream 수정안

`upstream-prs/`에는 `makenotion/notion-mcp-server`에 보낼 패치, 재현 방법, 제안 브랜치 이름과 PR 본문을 보관합니다. 아직 PR을 열지 않았습니다.

## 범위

서비스는 loopback 주소에 바인딩되며 로컬 사용자 한 명을 위한 구성입니다. 번들은 upstream revision을 고정하고 문서에 적은 호환성 수정 두 개를 적용합니다. 데모 자료와 자격 증명은 모두 가짜입니다.

## 기여

이슈와 풀 리퀘스트를 환영합니다. 번들 빌드와 리뷰 방식은 [CONTRIBUTING.md](CONTRIBUTING.md)에 있습니다.

## 라이선스

MIT입니다. Notion과 제휴하지 않은 비공식 커뮤니티 도구입니다.
