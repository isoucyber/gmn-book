# GMN BOOK OFFLINE

Aplicativo de gerenciamento de biblioteca escolar que funciona **100% offline**, com banco de dados **local e criptografado** em cada aparelho. Versões instaláveis para **Windows (.exe)** e **Android (.apk / .aab)**, a partir de uma única base de código Flutter.

- Instaladores prontos: aba **Releases** do repositório (gerados e testados pelo GitHub Actions).
- Manual de uso: [`docs/MANUAL.md`](docs/MANUAL.md)
- Estado do projeto, o que foi testado e o que falta: [`PROJECT_STATUS.md`](PROJECT_STATUS.md)

## Arquitetura

```
lib/
  core/        utilitários (UUID, datas, busca tolerante, ISBN), erros
  data/        banco SQLite (Drift) — schema SQL, migrations, helpers
  security/    papéis e permissões, Argon2id, AES-256-GCM
  services/    regras de negócio (cada método verifica a permissão da sessão)
    auth_service.dart        primeiro acesso, login, bloqueio, recuperação
    user_service.dart        usuários (HOST, AUXILIAR, USER)
    catalog_service.dart     acervo, exemplares/tombo, busca FTS5 + tolerante, capas
    circulation_service.dart empréstimo, devolução, renovação, prazos, desfazer
    due_control_service.dart controle de devoluções, notificações, cobrança
    dashboard_service.dart   indicadores do painel
    backup_service.dart      backup .gmnbak versionado/criptografado e restauração
    settings_service.dart    regras e calendário da biblioteca
    isbn_lookup.dart         sugestão por ISBN (Google Books / Open Library), opcional
  ui/          interface Material 3 adaptativa (menu lateral ≥ 900 px, barra inferior no celular)
  library.dart contexto: abre o banco, pastas, recuperação, troca segura de arquivo
test/                testes de serviços (com simulação de datas) e de interface
integration_test/    teste executado no Windows e no emulador Android reais
installer/windows/   script Inno Setup
tool/                patch dos projetos nativos, ícones, scripts de CI
```

### Decisões técnicas

| Tema | Decisão |
|---|---|
| Banco | SQLite via **Drift** (conexão em isolate, transações, migrations). Schema escrito em SQL e acessado só por consultas parametrizadas. |
| Criptografia do banco | **SQLite3MultipleCiphers** (build hooks do pacote `sqlite3` 3.x). Chave aleatória de 256 bits guardada no armazenamento seguro do sistema (Android Keystore / Windows Credential Manager via `flutter_secure_storage`). |
| IDs | UUID v4 em todas as tabelas, para permitir mesclar backups de aparelhos diferentes no futuro. |
| Datas | `created_at`/`updated_at` em ms; datas de calendário em `AAAA-MM-DD`. Situação "próximo do vencimento" e "atrasado" é **calculada**, nunca gravada. |
| Integridade | Chaves estrangeiras, `CHECK`, índice único parcial que impede um exemplar em dois empréstimos ativos, atualização condicional dentro de transação, `PRAGMA integrity_check` na abertura, modo WAL. |
| Auditoria | Tabela `audit_logs` com *triggers* que rejeitam `UPDATE`/`DELETE`. Hashes de senha nunca são registrados. |
| Senhas | Argon2id (m=19 MiB, t=2, p=1), em isolate. Bloqueio após N tentativas. Sem senha padrão. Código de recuperação offline (uso único). |
| Permissões | Verificadas **nos serviços** (`Session.require`), não apenas na interface. |
| Backup | Formato `.gmnbak` próprio e versionado: cabeçalho JSON + `gzip(JSON)`; com senha, AES-256-GCM com chave Argon2id. SHA-256 + conferência de contagens antes de restaurar. Restauração monta um banco novo à parte, verifica e só então troca; o banco anterior é guardado. |
| Busca | Índice FTS5 + correspondência tolerante a acentos e erros de digitação. |
| Projetos nativos | Gerados no CI por `flutter create` e ajustados por `tool/patch_platforms.py` (nome, ícone, permissões, assinatura). |

## Compilar localmente

Requisitos: Flutter stable (testado com 3.47.x / Dart 3.13), Python 3.

```bash
flutter create --platforms=windows,android --org br.com.gmnbook --project-name gmn_book --no-pub .
python tool/patch_platforms.py
flutter pub get
flutter test                      # testes de serviços e interface
flutter build windows --release   # Windows (precisa do Visual Studio com C++)
flutter build apk --release       # Android
```

Instalador Windows: `iscc /DAppVersion=1.0.0 installer\windows\gmn_book.iss` (Inno Setup 6).

## CI (GitHub Actions)

`.github/workflows/build.yml`:

1. **Testes** (Ubuntu): `flutter analyze` + `flutter test`.
2. **Windows**: build release → inclui runtime do Visual C++ → instalador Inno Setup → instala silenciosamente, abre o app sem Flutter no PATH, confere banco criado e criptografado, reabre, desinstala, confirma que os dados ficaram, reinstala → teste de integração no Windows real.
3. **Android**: APK + AAB (assinados com a chave do repositório, se configurada).
4. **Android no emulador**: instala o APK de release, abre, reabre, e roda o teste de integração no aparelho.
5. **Release**: em tags `v*` ou execução manual com "release" marcado, publica os instaladores e `SHA256SUMS.txt`.

### Chave de assinatura Android

Para que novas versões do APK possam ser instaladas **por cima** da anterior (mantendo os dados), todas precisam ser assinadas com a mesma chave. Cadastre em *Settings → Secrets and variables → Actions*:

| Segredo | Conteúdo |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | arquivo `.jks` em base64 |
| `ANDROID_KEYSTORE_PASSWORD` | senha do keystore |
| `ANDROID_KEY_ALIAS` | alias da chave |
| `ANDROID_KEY_PASSWORD` | senha da chave |

Sem esses segredos o build continua, mas o APK sai assinado com uma chave de depuração temporária.
