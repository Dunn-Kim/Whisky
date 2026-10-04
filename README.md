<div align="center">

  # Whisky 🥃 — Dunn-Kim fork
  *Wine but a bit stronger*

  > 개인 포크입니다. [frankea/Whisky](https://github.com/frankea/Whisky)(원작 [whisky-app/whisky](https://github.com/whisky-app/whisky)를 이어가는 커뮤니티 포크)를 기반으로, 필요한 변경만 골라 받으면서 독자적으로 수정합니다.
  >
  > A personal fork of [frankea/Whisky](https://github.com/frankea/Whisky), the community continuation of [whisky-app/whisky](https://github.com/whisky-app/whisky). Upstream changes are taken selectively; the fork carries its own fixes. Not affiliated with either project or getwhisky.app.

  [한국어](#한국어) · [English](#english) · [Changelog](CHANGELOG.md)

</div>

<img width="650" alt="Whisky in action" src="./images/demo.gif">

---

## 한국어

### 이 포크에 대하여

Whisky는 Wine을 SwiftUI로 감싼 macOS 앱입니다. 보틀을 만들고 Windows 앱과 게임을 설치·실행할 수 있습니다. 이 포크는 그 위에 다음 원칙으로 운영합니다.

- **upstream은 골라서 받습니다.** frankea/Whisky의 변경을 그대로 병합하지 않고, 필요한 커밋만 `cherry-pick -x`로 가져옵니다.
- **자동 업데이트는 꺼져 있습니다.** Sparkle 업데이터는 시작하지 않고, WhiskyWine 런타임 업데이트 확인도 기본으로 꺼져 있습니다(설정에서 다시 켤 수 있음). upstream 배포 피드를 따르면 포크 빌드가 덮어써지기 때문입니다.
- **바이너리는 배포하지 않습니다.** 공증되지 않은 개인 빌드라서, 릴리스에는 태그와 변경 내역만 올립니다. 직접 빌드해서 사용합니다.

### 주요 변경 (upstream 3.7.0 대비)

- **macOS 27 대응:** 메이저 업데이트로 Rosetta 2가 사라지면 앱 시작 시 설치 화면을 띄웁니다(이전에는 모든 실행이 "Bad CPU type"으로 실패).
- **한글 표시:** Wine의 한글 대체 글꼴(`Noto Sans CJK KR`, 맑은 고딕, 굴림 등)을 macOS의 Apple SD Gothic Neo에 연결해, 내장 브라우저 공지창과 런처의 한글이 □로 나오지 않습니다.
- **Finder로 연 exe의 언어:** 파일 열기 창에서 언어(Locale)를 고르고 exe별로 저장합니다.
- **프레임 제한:** 보틀·프로그램별 FPS 상한(DXVK, DXMT)으로 GPU 발열과 전력을 줄입니다.
- **DXMT MetalFX 업스케일링** 토글, 백엔드 전환 시 남은 번역 DLL 정리, DXVK 병렬 셰이더 컴파일, App Nap 방지 기본값.
- **게임 DB:** Mecharashi 항목, ZFGame Browser 런처 감지.
- **트러블슈팅 위저드:** 오디오 장치, 최근 로그, 런처 정보를 실제로 채워서 검사가 동작합니다.
- **정리:** 호출되지 않는 코드 약 6,000줄 삭제.
- **upstream 반영:** 로그 덮어쓰기, 셸 따옴표 보안 수정, d3d12 처리 등(목록은 CHANGELOG 참고).

### 빌드와 설치

요구 사항: Apple Silicon Mac, macOS 15 이상, Xcode(27에서 확인), Rosetta 2.

```sh
# Rosetta 2가 없다면
softwareupdate --install-rosetta --agree-to-license

# ad-hoc 서명으로 Release 빌드
xcodebuild -project Whisky.xcodeproj -scheme Whisky -configuration Release \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Whisky-local \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  SKIP_SWIFTLINT_BUILD_PHASE=YES ENABLE_HARDENED_RUNTIME=NO build

# 복사가 아니라 이동: 빌드 폴더에 두 번째 Whisky.app을 남기지 않습니다
APP=~/Library/Developer/Xcode/DerivedData/Whisky-local/Build/Products/Release/Whisky.app
rm -rf /Applications/Whisky.app && mv "$APP" /Applications/Whisky.app
```

- `SKIP_SWIFTLINT_BUILD_PHASE=YES`: SwiftLint가 설치되어 있지 않으면 빌드 단계가 실패하기 때문입니다.
- `ENABLE_HARDENED_RUNTIME=NO`: ad-hoc 서명에 hardened runtime을 켜면 내장된 Sparkle.framework가 로드되지 않아 앱이 시작하자마자 종료됩니다.
- 처음 실행하면 Wine 런타임(WhiskyWine)을 내려받고 기본 보틀을 만듭니다.

### upstream 동기화

```sh
git remote add upstream https://github.com/frankea/Whisky.git
git remote set-url --push upstream DISABLED_no_push_to_upstream  # upstream으로는 절대 push하지 않음
git fetch upstream
git log --oneline --no-merges main..upstream/main   # 아직 받지 않은 커밋
git cherry-pick -x <commit>                         # 필요한 것만
```

### 릴리스

태그는 날짜 기반 `fork-YYYY.MM.DD`이고, upstream의 `app-v*`·`v*` 태그와 겹치지 않습니다. GitHub 릴리스에는 변경 내역만 있고 앱 파일은 없습니다.

---

## English

### About this fork

Whisky is a native SwiftUI wrapper for Wine on macOS: make bottles, install and run Windows apps and games. This fork runs on three rules:

- **Upstream is taken selectively.** Changes from frankea/Whisky are not merged wholesale; the ones needed are brought in with `cherry-pick -x`.
- **Automatic updates are off.** The Sparkle updater is never started and the WhiskyWine runtime update check defaults to off (Settings can turn it back on), because following upstream's feed would replace the fork build.
- **No binaries are published.** Builds are ad-hoc signed and not notarized, so releases carry tags and notes only. Build it yourself.

### What's different (since upstream 3.7.0)

- **macOS 27:** when a major update removes Rosetta 2, setup opens at launch (before, every launch failed with "Bad CPU type").
- **Korean text:** wine's Hangul fallbacks (`Noto Sans CJK KR`, Malgun Gothic, Gulim, …) map to the host's Apple SD Gothic Neo, so embedded-browser notices and launchers stop drawing boxes.
- **Locale for files opened from Finder:** the open sheet has a Locale picker, saved per executable.
- **Frame rate cap** per bottle and per program (DXVK, DXMT), to cut GPU heat and power.
- **DXMT MetalFX upscaling** toggle, stale translation DLLs restored on backend switch, parallel DXVK shader compilation, App Nap prevention by default.
- **Game database:** a Mecharashi entry and ZFGame Browser launcher detection.
- **Guided troubleshooting:** the wizard now fills the audio device, recent log and launcher its checks read.
- **Cleanup:** about 6,000 lines nothing called were removed.
- **From upstream:** the log-overwrite fix, the shell-quoting security fix, d3d12 handling and more (see the changelog).

### Build and install

Requires an Apple Silicon Mac, macOS 15 or later, Xcode (verified with 27) and Rosetta 2.

```sh
# Without Rosetta 2
softwareupdate --install-rosetta --agree-to-license

# Release build, ad-hoc signed
xcodebuild -project Whisky.xcodeproj -scheme Whisky -configuration Release \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Whisky-local \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  SKIP_SWIFTLINT_BUILD_PHASE=YES ENABLE_HARDENED_RUNTIME=NO build

# Move, don't copy, so no second Whisky.app stays in the build folder
APP=~/Library/Developer/Xcode/DerivedData/Whisky-local/Build/Products/Release/Whisky.app
rm -rf /Applications/Whisky.app && mv "$APP" /Applications/Whisky.app
```

- `SKIP_SWIFTLINT_BUILD_PHASE=YES`: the build phase fails when SwiftLint isn't installed.
- `ENABLE_HARDENED_RUNTIME=NO`: with hardened runtime on an ad-hoc signature, the embedded Sparkle.framework is refused and the app exits at launch.
- On first run the app downloads the Wine runtime (WhiskyWine) and sets up a default bottle.

### Syncing upstream

```sh
git remote add upstream https://github.com/frankea/Whisky.git
git remote set-url --push upstream DISABLED_no_push_to_upstream  # never push upstream
git fetch upstream
git log --oneline --no-merges main..upstream/main   # commits not taken yet
git cherry-pick -x <commit>                         # only the ones needed
```

### Releases

Tags are date based, `fork-YYYY.MM.DD`, and never collide with upstream's `app-v*` or `v*` tags. GitHub releases carry notes only, no app files.

---

## 크레딧 · 라이선스 / Credits & License

Whisky is possible thanks to the magic of several projects:

- [msync](https://github.com/marzent/wine-msync) by marzent
- [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) by Gcenx and doitsujin
- [DXMT](https://github.com/3Shain/dxmt) by 3Shain
- [MoltenVK](https://github.com/KhronosGroup/MoltenVK) by KhronosGroup
- [Sparkle](https://github.com/sparkle-project/Sparkle) by sparkle-project
- [SemanticVersion](https://github.com/SwiftPackageIndex/SemanticVersion) by SwiftPackageIndex
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) by Apple
- [CrossOver](https://www.codeweavers.com/crossover) by CodeWeavers and WineHQ
- D3DMetal by Apple

Special thanks to Gcenx, ohaiibuzzle, Nat Brown, [Isaac Marovitz](https://github.com/IsaacMarovitz) (original author) and [@frankea](https://github.com/frankea) (community fork maintainer).

GPL-3.0, see [LICENSE](LICENSE).

<table>
  <tr>
    <td>
        <picture>
          <source media="(prefers-color-scheme: dark)" srcset="./images/cw-dark.png">
          <img src="./images/cw-light.png" width="500">
        </picture>
    </td>
    <td>
        Whisky doesn't exist without CrossOver. If you want a fully-supported commercial Wine experience on macOS, check out <a href="https://www.codeweavers.com/crossover">CrossOver</a> from CodeWeavers. (This fork has no affiliate arrangement and receives nothing from CrossOver sales.)
    </td>
  </tr>
</table>
