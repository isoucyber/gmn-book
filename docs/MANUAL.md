# Manual do GMN BOOK OFFLINE

## 1. Instalação

**Windows 10/11 (64 bits)**
1. Baixe `GMN-BOOK-Setup-<versão>-x64.exe` na página de Releases.
2. Execute. Como o instalador ainda não tem certificado de assinatura de código, o Windows pode mostrar "O Windows protegeu o computador": clique em **Mais informações → Executar assim mesmo**.
3. Não é preciso ser administrador. Um atalho é criado no Menu Iniciar (e, se marcado, na área de trabalho).

**Android**
1. Copie `GMN-BOOK-<versão>.apk` para o aparelho e toque nele.
2. Autorize "instalar apps de fontes desconhecidas" para o aplicativo usado (Arquivos, Chrome etc.).

Nenhuma ferramenta de programação é necessária. O aplicativo funciona sem internet.

## 2. Onde ficam os dados

- **Windows:** `%APPDATA%\GMN BOOK\GMN BOOK\data` (o arquivo do banco é criptografado).
- **Android:** área privada do aplicativo.

Atualizar o aplicativo **não apaga** os dados. No Windows, nem desinstalar apaga os dados.

> **Importante:** cada aparelho tem o seu próprio banco. Um empréstimo registrado no notebook **não aparece** no celular até que você faça um backup no notebook e o restaure no celular. Não existe sincronização automática.

## 3. Primeiro acesso

Na primeira abertura, o assistente pede:
1. **Escola** — nome, endereço e ano letivo.
2. **Administrador (HOST)** — seu nome, usuário e senha (mínimo 8 caracteres, com letras e números). Não existe senha padrão.
3. **Regras** — prazo padrão de empréstimo, limite de livros por aluno, dias de alerta e se alunos podem criar a própria conta.

No final aparece o **código de recuperação** (formato `XXXX-XXXX-XXXX-XXXX`). Guarde-o: ele permite criar uma nova senha se você esquecer a atual, mesmo sem internet (tela de login → "Esqueci a senha"). Depois de usado, um novo código é gerado.

## 4. Perfis

| Perfil | O que pode fazer |
|---|---|
| **HOST (administrador)** | Tudo: acervo, usuários, empréstimos, regras, calendário, backup/restauração, auditoria. Pode haver vários HOSTs. |
| **Auxiliar / Monitor** | Balcão (empréstimos e devoluções), consultas e controle de devoluções. Não altera regras, não cadastra livros, não restaura backup. |
| **Leitor (USER)** | Catálogo, favoritos, os próprios empréstimos, prazos, histórico e avisos. Não vê dados de outras pessoas. |

As permissões são verificadas pelo próprio aplicativo em cada operação — não basta esconder botões.

## 5. Cadastro de livros

**Catálogo → Novo livro** (ou `Ctrl+N` no Windows).

- **ISBN:** digite, leia com leitor de código de barras USB (clique no campo e leia — o leitor funciona como teclado) ou use a câmera no Android. O botão de busca preenche título, autor, editora etc. **quando há internet**; revise antes de salvar. Sem internet, preencha manualmente.
- Se o ISBN ou o título já existirem, o aplicativo oferece **adicionar exemplar** ao título existente.
- **Regras do título:** prazo próprio (ex.: Dom Casmurro = 14 dias), se permite renovação e quantas, se permite reserva e se há restrição de empréstimo.
- **Exemplares:** cada um recebe um **número de tombo** único, que também é o código usado no balcão. Mais exemplares: abra o livro → menu ⋮ → **Adicionar exemplares**.
- **Situação do exemplar** (manutenção, extraviado, danificado, baixado, uso local): abra o livro e use ⋮ ao lado do exemplar.
- **Arquivar** remove o título do catálogo sem apagar o histórico.

## 6. Balcão (empréstimo e devolução)

**Empréstimo** (`F2`):
1. Leia ou digite a **carteirinha** (código `U000123`), a matrícula ou o usuário — ou procure pelo nome.
2. Leia o **tombo** do exemplar (ou o ISBN, que escolhe um exemplar disponível), ou procure no catálogo.
3. A data de devolução é calculada automaticamente pelo prazo do título (ou o padrão da biblioteca), pulando fins de semana fechados, feriados e recessos do calendário. Você pode mudar o prazo em dias ou escolher a data manualmente.
4. **Confirmar empréstimo**. Por alguns segundos aparece **Desfazer**.

Bloqueios: atraso, pendência de perda/dano, limite de livros ou título restrito. Um administrador pode liberar informando uma justificativa (fica registrada na auditoria).

**Devolução** (`F3`): leia o tombo, marque o estado de conservação (bom, regular, danificado) ou "perda" e confirme. A disponibilidade é atualizada na hora.

## 7. Controle de devoluções

Menu **Devoluções**, com três abas:
- **Próximos do vencimento** — ex.: "João — Dom Casmurro — faltam 3 dias".
- **Em atraso** — nome, livro, data prevista, dias de atraso e contato (se autorizado no cadastro).
- **Devolvidos** — histórico.

Em cada empréstimo: **Mensagem de cobrança** (texto pronto para colar no WhatsApp, e-mail ou SMS, com modelo editável em Regras), **Renovar** e **Alterar prazo**.

**Quem está com cada livro?** — pesquise um título e veja quem está com cada exemplar, desde quando, até quando e quantos dias faltam/atrasou.
**Usuários com empréstimos** — pesquise uma pessoa e veja todos os livros com ela.

## 8. Alertas

Os dias de alerta (padrão: 7, 3 e 1 dia antes, no dia e após o vencimento) são configurados em **Regras e calendário**. O aplicativo verifica os prazos ao entrar e a cada 30 minutos, sem internet, e gera avisos em **Notificações** (para a equipe) e em **Avisos** (para o leitor, no aparelho onde o empréstimo está registrado).

## 9. Portal do leitor

O aluno entra com o próprio usuário e vê: livros com ele, data de devolução e dias restantes, favoritos, histórico e avisos. Se a biblioteca permitir, pode renovar pelo portal.

Cadastro de alunos: pela biblioteca (Usuários → Novo usuário; o aluno troca a senha no primeiro acesso) ou pelo próprio aluno na tela de login, conforme a regra escolhida (livre, com aprovação, ou desativado). Para menores de idade é registrado o consentimento do responsável.

## 10. Backup e restauração

Menu **Backup e restauração** (somente HOST).

- **Criar backup:** gera um arquivo `.gmnbak` com todos os dados (inclusive capas). Recomendado: proteger com senha (criptografia AES-256). **Sem a senha não é possível restaurar.** Salve em pendrive, HD externo ou nuvem pessoal.
- **Restaurar:** escolha o arquivo, informe a senha do backup, confira o resumo (escola, data, quantidade de livros/usuários/empréstimos) e confirme com a **sua** senha de administrador. Todos os dados do aparelho são **substituídos**; antes disso, uma cópia automática do estado atual é guardada.
- **Transferir para outro aparelho:** crie o backup no aparelho de origem e restaure no de destino.
- O Painel avisa quando o último backup está mais antigo que o intervalo configurado.

Se o banco for danificado, o aplicativo abre uma tela de recuperação que permite restaurar uma cópia automática ou um arquivo de backup. Nada é apagado.

## 11. Segurança

- Senhas guardadas com Argon2id; o banco inteiro é criptografado.
- Após 5 senhas erradas (configurável), a conta fica bloqueada por 15 minutos; um HOST pode desbloquear.
- A sessão é encerrada após 10 minutos sem uso (configurável).
- Toda ação importante fica na **Auditoria**, que não pode ser editada nem apagada.

## 12. Atalhos (Windows)

| Tecla | Ação |
|---|---|
| `Ctrl+K` | Busca global (livro, usuário, empréstimo) |
| `F2` | Balcão — empréstimo |
| `F3` | Balcão — devolução |
| `Ctrl+N` | Novo livro |
