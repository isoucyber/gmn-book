/// Estrutura do banco local (versao 1).
///
/// Convencoes:
/// * IDs em TEXT (UUID v4) para permitir mesclar backups entre aparelhos.
/// * created_at / updated_at / deleted_at em milissegundos (INTEGER).
///   updated_at e a base para nao sobrescrever dados mais recentes na importacao.
/// * Datas de calendario (emprestimo, vencimento, feriados) em TEXT 'AAAA-MM-DD'.
/// * Status "proximo do vencimento" e "atrasado" NAO sao gravados: sao
///   calculados a partir de due_date e da data atual.
const int kSchemaVersion = 1;

const List<String> schemaV1 = [
  '''CREATE TABLE app_meta (
    key TEXT PRIMARY KEY,
    value TEXT
  )''',
  '''CREATE TABLE roles (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT
  )''',
  "INSERT INTO roles (id, name, description) VALUES "
      "('host','Administrador','Controle completo da biblioteca'),"
      "('staff','Auxiliar/Monitor','Registra empréstimos e devoluções'),"
      "('user','Leitor','Aluno ou leitor')",
  '''CREATE TABLE users (
    id TEXT PRIMARY KEY,
    role_id TEXT NOT NULL REFERENCES roles(id),
    name TEXT NOT NULL CHECK (length(trim(name)) > 0),
    name_norm TEXT NOT NULL,
    username TEXT NOT NULL COLLATE NOCASE UNIQUE,
    password_hash TEXT NOT NULL,
    card_code TEXT NOT NULL UNIQUE,
    enrollment TEXT,
    class_name TEXT,
    grade TEXT,
    shift TEXT,
    school_year TEXT,
    status TEXT NOT NULL DEFAULT 'active'
      CHECK (status IN ('active','pending','inactive','transferred','graduated')),
    email TEXT,
    phone TEXT,
    guardian_name TEXT,
    guardian_phone TEXT,
    contact_authorized INTEGER NOT NULL DEFAULT 0,
    is_minor INTEGER NOT NULL DEFAULT 0,
    consent_at INTEGER,
    guardian_consent_at INTEGER,
    failed_attempts INTEGER NOT NULL DEFAULT 0,
    locked_until INTEGER,
    must_change_password INTEGER NOT NULL DEFAULT 0,
    last_login_at INTEGER,
    created_by TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER
  )''',
  'CREATE INDEX ix_users_role ON users(role_id)',
  'CREATE INDEX ix_users_name ON users(name_norm)',
  'CREATE UNIQUE INDEX ux_users_enrollment ON users(enrollment) WHERE enrollment IS NOT NULL AND enrollment <> \'\'',
  '''CREATE TABLE recovery_codes (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id),
    code_hash TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    used_at INTEGER
  )''',
  '''CREATE TABLE library_settings (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated_at INTEGER NOT NULL
  )''',
  '''CREATE TABLE authors (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    name_norm TEXT NOT NULL UNIQUE,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER
  )''',
  '''CREATE TABLE publishers (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    name_norm TEXT NOT NULL UNIQUE,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER
  )''',
  '''CREATE TABLE categories (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    name_norm TEXT NOT NULL UNIQUE,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER
  )''',
  '''CREATE TABLE books (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL CHECK (length(trim(title)) > 0),
    subtitle TEXT,
    isbn TEXT,
    publisher_id TEXT REFERENCES publishers(id),
    category_id TEXT REFERENCES categories(id),
    year INTEGER CHECK (year IS NULL OR (year BETWEEN 0 AND 2200)),
    genre TEXT,
    language TEXT,
    pages INTEGER CHECK (pages IS NULL OR pages >= 0),
    description TEXT,
    cover_file TEXT,
    location TEXT,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','archived')),
    loan_days INTEGER CHECK (loan_days IS NULL OR loan_days BETWEEN 1 AND 365),
    allow_renewal INTEGER NOT NULL DEFAULT 1,
    max_renewals INTEGER NOT NULL DEFAULT 1 CHECK (max_renewals >= 0),
    allow_reservation INTEGER NOT NULL DEFAULT 1,
    restricted INTEGER NOT NULL DEFAULT 0,
    restriction_note TEXT,
    search_text TEXT NOT NULL DEFAULT '',
    created_by TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER
  )''',
  'CREATE INDEX ix_books_isbn ON books(isbn)',
  'CREATE INDEX ix_books_category ON books(category_id)',
  'CREATE INDEX ix_books_status ON books(status)',
  '''CREATE TABLE book_authors (
    book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    author_id TEXT NOT NULL REFERENCES authors(id),
    role TEXT NOT NULL DEFAULT 'autor',
    position INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (book_id, author_id, role)
  )''',
  'CREATE INDEX ix_book_authors_author ON book_authors(author_id)',
  '''CREATE TABLE book_copies (
    id TEXT PRIMARY KEY,
    book_id TEXT NOT NULL REFERENCES books(id),
    accession_number INTEGER NOT NULL UNIQUE,
    barcode TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'available' CHECK (status IN
      ('available','loaned','reserved','maintenance','lost','damaged','withdrawn','reference')),
    condition TEXT NOT NULL DEFAULT 'bom' CHECK (condition IN ('bom','regular','danificado')),
    acquisition TEXT,
    notes TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER
  )''',
  'CREATE INDEX ix_copies_book ON book_copies(book_id)',
  'CREATE INDEX ix_copies_status ON book_copies(status)',
  '''CREATE TABLE copy_status_history (
    id TEXT PRIMARY KEY,
    copy_id TEXT NOT NULL REFERENCES book_copies(id),
    old_status TEXT,
    new_status TEXT NOT NULL,
    reason TEXT,
    by_user TEXT,
    at INTEGER NOT NULL
  )''',
  'CREATE INDEX ix_copy_hist_copy ON copy_status_history(copy_id)',
  '''CREATE TABLE loans (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id),
    book_id TEXT NOT NULL REFERENCES books(id),
    copy_id TEXT NOT NULL REFERENCES book_copies(id),
    loan_date TEXT NOT NULL,
    due_date TEXT NOT NULL CHECK (due_date >= loan_date),
    return_date TEXT,
    returned_at INTEGER,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','returned','cancelled')),
    renewals INTEGER NOT NULL DEFAULT 0,
    condition_out TEXT,
    condition_in TEXT,
    notes TEXT,
    override_reason TEXT,
    created_by TEXT NOT NULL REFERENCES users(id),
    returned_by TEXT REFERENCES users(id),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )''',
  // Impede, no proprio banco, que um exemplar fique com duas pessoas ao mesmo tempo.
  "CREATE UNIQUE INDEX ux_loans_active_copy ON loans(copy_id) WHERE status = 'active'",
  'CREATE INDEX ix_loans_user ON loans(user_id, status)',
  'CREATE INDEX ix_loans_book ON loans(book_id, status)',
  'CREATE INDEX ix_loans_due ON loans(status, due_date)',
  '''CREATE TABLE renewals (
    id TEXT PRIMARY KEY,
    loan_id TEXT NOT NULL REFERENCES loans(id),
    old_due_date TEXT NOT NULL,
    new_due_date TEXT NOT NULL,
    by_user TEXT NOT NULL,
    at INTEGER NOT NULL
  )''',
  '''CREATE TABLE reservations (
    id TEXT PRIMARY KEY,
    book_id TEXT NOT NULL REFERENCES books(id),
    user_id TEXT NOT NULL REFERENCES users(id),
    copy_id TEXT REFERENCES book_copies(id),
    status TEXT NOT NULL DEFAULT 'waiting'
      CHECK (status IN ('waiting','ready','fulfilled','cancelled','expired')),
    ready_until TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )''',
  'CREATE INDEX ix_reservations_book ON reservations(book_id, status, created_at)',
  '''CREATE TABLE favorites (
    user_id TEXT NOT NULL REFERENCES users(id),
    book_id TEXT NOT NULL REFERENCES books(id),
    created_at INTEGER NOT NULL,
    PRIMARY KEY (user_id, book_id)
  )''',
  '''CREATE TABLE notifications (
    id TEXT PRIMARY KEY,
    user_id TEXT REFERENCES users(id),
    audience TEXT NOT NULL DEFAULT 'staff' CHECK (audience IN ('staff','user')),
    kind TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT,
    ref_id TEXT,
    dedupe_key TEXT UNIQUE,
    created_at INTEGER NOT NULL,
    read_at INTEGER
  )''',
  'CREATE INDEX ix_notifications_user ON notifications(user_id, read_at)',
  '''CREATE TABLE holidays (
    id TEXT PRIMARY KEY,
    date TEXT NOT NULL UNIQUE,
    description TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )''',
  '''CREATE TABLE ai_conversations (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id),
    title TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )''',
  '''CREATE TABLE ai_messages (
    id TEXT PRIMARY KEY,
    conversation_id TEXT NOT NULL REFERENCES ai_conversations(id) ON DELETE CASCADE,
    sender TEXT NOT NULL CHECK (sender IN ('user','assistant','system')),
    content TEXT NOT NULL,
    created_at INTEGER NOT NULL
  )''',
  '''CREATE TABLE backup_history (
    id TEXT PRIMARY KEY,
    kind TEXT NOT NULL,
    file_name TEXT,
    size_bytes INTEGER,
    encrypted INTEGER NOT NULL DEFAULT 0,
    by_user TEXT,
    at INTEGER NOT NULL
  )''',
  '''CREATE TABLE audit_logs (
    id TEXT PRIMARY KEY,
    at INTEGER NOT NULL,
    user_id TEXT,
    user_name TEXT,
    action TEXT NOT NULL,
    entity TEXT,
    entity_id TEXT,
    old_value TEXT,
    new_value TEXT,
    details TEXT
  )''',
  'CREATE INDEX ix_audit_at ON audit_logs(at)',
  // Auditoria imutavel: nenhuma alteracao ou exclusao e aceita pelo banco.
  '''CREATE TRIGGER audit_logs_no_update BEFORE UPDATE ON audit_logs
     BEGIN SELECT RAISE(ABORT, 'audit log is immutable'); END''',
  '''CREATE TRIGGER audit_logs_no_delete BEFORE DELETE ON audit_logs
     BEGIN SELECT RAISE(ABORT, 'audit log is immutable'); END''',
];

/// Indice FTS5 do catalogo (criado a parte; se o SQLite nao tiver FTS5,
/// a busca cai para o modo tolerante em memoria).
const String ftsCreate =
    "CREATE VIRTUAL TABLE IF NOT EXISTS books_fts USING fts5(book_id UNINDEXED, content, tokenize='unicode61 remove_diacritics 2')";

/// Ordem segura para exportar/importar (respeita chaves estrangeiras).
const List<String> backupTables = [
  'app_meta',
  'library_settings',
  'users',
  'recovery_codes',
  'authors',
  'publishers',
  'categories',
  'books',
  'book_authors',
  'book_copies',
  'copy_status_history',
  'loans',
  'renewals',
  'reservations',
  'favorites',
  'notifications',
  'holidays',
  'ai_conversations',
  'ai_messages',
  'backup_history',
  'audit_logs',
];
