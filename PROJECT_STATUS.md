# PROJECT_STATUS — GMN BOOK OFFLINE

Atualizado em 03/11/2026. Escopo desta entrega: **Fase 1 (núcleo da biblioteca)** do item 37 do documento de requisitos, para **Windows e Android** (iOS fora do escopo, a pedido).

## Como foi compilado e testado

Tudo é compilado e testado pelo GitHub Actions (`.github/workflows/build.yml`), com Flutter 3.47.9 / Dart 3.13.7 (stable). Nada foi declarado como testado sem execução real no CI.

| Verificação | Onde roda | Situação |
|---|---|---|
| Análise estática (`flutter analyze`) | Ubuntu | ✅ sem erros |
| 32 testes de serviços e interface (`flutter test`) com simulação de datas | Ubuntu | ✅ |
| Build Windows release + instalador Inno Setup (.exe) | Windows Server (runner) | ✅ |
| Instalação silenciosa, app abre com PATH mínimo (sem Flutter/Dart), banco criado em `%APPDATA%` e **criptografado**, reabertura, desinstalação **preservando dados**, reinstalação sobre dados existentes | Windows (runner) | ✅ |
| Teste de integração no Windows real (setup → login → livro → empréstimo → alerta com data simulada → devolução → backup criptografado → fechar/reabrir → restauração → tela de login → painel) | Windows (runner) | ✅ |
| Build APK + AAB release | Ubuntu | ✅ |
| APK de release instalado no emulador Android 11 (API 30), aberto e reaberto sem erros | Emulador | ✅ |
| Mesmo teste de integração no Android (inclui login pela interface e painel em tela de celular) | Emulador | ✅ |

**Limites honestos do "ambiente limpo":** os runners do GitHub têm ferramentas de desenvolvimento instaladas. O teste remove Flutter/Dart do PATH do processo e roda o app instalado fora da pasta do projeto, e o pacote inclui o runtime do Visual C++ (app-local), mas **não** é uma máquina virgem. Recomenda-se um teste manual em um PC Windows comum e em um celular Android físico antes de distribuir para a escola.

## Concluído (Fase 1)

- Assistente de primeira execução (escola, HOST, regras); sem credenciais padrão; código de recuperação offline de uso único; múltiplos HOSTs.
- Perfis HOST, AUXILIAR/MONITOR e USER com permissões verificadas nos serviços.
- Login com bloqueio por tentativas, expiração de sessão por inatividade, troca obrigatória de senha em contas criadas pela biblioteca, autocadastro configurável (livre / aprovação / desativado) com consentimento (e do responsável para menores).
- Banco SQLite local **criptografado** (SQLite3MultipleCiphers), chave no armazenamento seguro do sistema; UUIDs; chaves estrangeiras, índices, `CHECK`, transações; migrations versionadas com cópia automática antes de migrar; WAL; `integrity_check` na abertura com tela de recuperação.
- Acervo: livros com todos os campos do item 6, múltiplos autores, editora/categoria, capa (arquivo local), localização; **regras por título** (prazo, renovação e limite, reserva, restrição); exemplares com **tombo** único; situação do exemplar (disponível, emprestado, manutenção, extraviado, danificado, baixado, uso local) com histórico; arquivamento.
- ISBN: leitor USB (Windows), câmera (Android), validação de dígito, preenchimento automático opcional (Google Books / Open Library) e detecção de duplicidade.
- Busca offline com FTS5 + tolerância a acentos e erros de digitação.
- Balcão rápido (carteirinha → exemplar), prazo automático pelo título/biblioteca pulando fins de semana e **calendário de feriados/recessos**, alteração manual do prazo, bloqueios (atraso, pendência, limite, restrição) com liberação justificada, devolução com estado de conservação/extravio, **desfazer** em 30 s, renovação com regras.
- Impede exemplar em dois empréstimos (regra + índice único no banco).
- **Controle de devoluções** (próximos / atrasados / devolvidos), **Quem está com cada livro?**, **Usuários com empréstimos ativos**, mensagens de cobrança com modelo editável.
- Alertas configuráveis (dias antes / no dia / após), notificações internas para equipe e leitor, verificação periódica offline.
- Painel com indicadores, gráficos e atividades recentes; aviso de backup atrasado.
- Portal do leitor (empréstimos, dias restantes, favoritos, histórico, avisos).
- Backup `.gmnbak` versionado, opcionalmente criptografado (AES-256-GCM + Argon2id), com capas; validação de integridade; restauração com pré-visualização, reconfirmação de senha, cópia automática prévia e troca segura do arquivo.
- Auditoria imutável (triggers no banco).
- Interface Material 3 adaptativa (menu lateral / barra inferior), tema claro/escuro, tamanho de fonte ajustável, busca global `Ctrl+K`, atalhos `F2`/`F3`/`Ctrl+N`.

## Pendências e decisões em aberto

| Item | Situação |
|---|---|
| Chave de assinatura Android nos segredos do repositório | **Pendente (ação do dono do repositório).** Sem ela, cada build do CI assina o APK com uma chave de depuração diferente e uma nova versão não instala por cima da anterior. Ver README → "Chave de assinatura Android". |
| Certificado de assinatura de código Windows | Não adquirido. O instalador funciona, mas o SmartScreen mostra aviso na primeira execução. |
| Notificações do sistema operacional (fora do app) | Fase 2. Hoje os alertas são internos (central de notificações). |
| Reservas com fila, empréstimo de férias, penalidades, turmas/promoção, importação por planilha, carteirinhas e etiquetas em PDF | Fase 2 (tabelas já previstas). |
| Relatórios exportáveis (PDF/CSV/XLSX) | Fase 2. |
| IA do leitor e IA administrativa | Fase 3 (tabelas `ai_conversations`/`ai_messages` já existem). |
| Inventário, aquisições, mesclagem de backups com tela de conflitos, anonimização/retenção LGPD | Fase 4. Hoje a restauração é "substituir tudo". |
| Compressão automática de capas | Hoje há limite de 3 MB por imagem. |
| `pubspec.lock` versionado | Recomendado após a primeira versão estável, para builds 100% reproduzíveis. |

## Decisões técnicas

Ver a tabela em `README.md`. Destaques: projetos nativos gerados no CI (`flutter create` + `tool/patch_platforms.py`); situações "próximo do vencimento"/"atrasado" sempre calculadas; portal do aluno pensado para o aparelho da biblioteca (cada aparelho tem seu banco, sem sincronização).
