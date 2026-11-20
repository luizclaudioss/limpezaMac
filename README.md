# LimpezaMac

Aplicativo nativo macOS (SwiftUI) para limpeza profunda de disco com suporte a privilégios **ROOT** via diálogo nativo de administrador do macOS.

## Recursos

- **Modo Dry-Run obrigatório:** Escaneia e calcula o tamanho exato de cada item antes de qualquer alteração.
- **Privilégios ROOT seguros:** Itens de sistema (`/Library/Caches`, `/Library/Logs`, `/private/tmp`, `/private/var/tmp`, `/private/var/log`, `/private/var/folders`, snapshots do Time Machine) solicitam autorização nativa do macOS (`osascript ... with administrator privileges`) apenas no momento da limpeza.
- **Proteção contra exclusão acidental:**
  - Lista restrita (allowlist) de diretórios permitidos no [`RootCleaner`](Sources/LimpezaMac/Services/RootCleaner.swift).
  - Níveis de segurança: **Seguro**, **Moderado** e **Atenção** (itens de atenção vêm desmarcados por padrão).
  - Proteção contra symlinks e diretórios protegidos pelo SIP.

## Categorias Escaneadas

1. **Caches de Usuário:** `~/Library/Caches`
2. **Caches do Sistema (ROOT):** `/Library/Caches` e `/private/var/folders/*/C`
3. **Temporários e Logs:** `~/Library/Logs`, `/Library/Logs`, `/private/var/log` (arquivos rotacionados/diagnósticos), `/private/tmp` e `/private/var/tmp` (> 24h)
4. **Sobras de Apps Desinstalados:** Pastas órfãs em `Application Support`, `Containers` e `Saved Application State` sem modificação há mais de 7 dias
5. **Caches de Desenvolvimento:** Xcode (`DerivedData`, `iOS DeviceSupport`, `Archives`, `CoreSimulator/Caches`), Homebrew, npm, Yarn, pnpm, pip, uv, CocoaPods, SwiftPM, Gradle e Cargo
6. **Navegadores:** Safari, Chrome, Edge, Brave e Firefox
7. **Lixeira e Downloads Antigos:** `~/.Trash` e itens em `~/Downloads` sem modificação há mais de 30 dias
8. **Time Machine:** Snapshots locais APFS (`tmutil listlocalsnapshots /`)

## Como compilar e executar

```bash
./build_app.sh
open LimpezaMac.app
```

> **Dica:** Para que o app consiga ler caches protegidos (como Safari), conceda **Acesso Total ao Disco** em *Ajustes do Sistema > Privacidade e Segurança > Acesso Total ao Disco*.
