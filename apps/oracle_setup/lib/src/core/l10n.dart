import 'package:flutter/foundation.dart';

/// Wizard localization (pt/en) — toggled from the step rail.
final l10n = L10n();

class L10n extends ChangeNotifier {
  String code = 'pt';

  void set(String c) {
    if (c == code) return;
    code = c;
    notifyListeners();
  }

  String t(String key) => (code == 'pt' ? _pt[key] : _en[key]) ?? _pt[key] ?? key;
}

const _pt = <String, String>{
  'step.welcome': 'Bem-vindo',
  'step.db': 'Banco de dados',
  'step.embed': 'Embeddings',
  'step.security': 'Segurança',
  'step.install': 'Instalar',
  'step.agents': 'Agentes',
  'step.finish': 'Concluir',
  'nav.back': 'Voltar',
  'nav.next': 'Avançar',
  'welcome.title': 'Bem-vindo ao Oracle AI',
  'welcome.body':
      'Este assistente instala e configura o banco de memória de longo prazo para os seus agentes de código (Claude Code, Codex, Cursor…).\n\nO que será feito:\n  1. Banco de dados (PostgreSQL + pgvector) — usa o seu, o Docker, ou instala um PostgreSQL portátil sem Docker;\n  2. Provedor de embeddings (local ou API);\n  3. Token de segurança dos hooks;\n  4. Migração do schema (e restauração de backup, se houver);\n  5. Configuração dos agentes (MCP + hooks).',
  'db.title': 'Banco de dados',
  'db.existing': 'Usar um PostgreSQL existente',
  'db.existingHint': 'Informe os dados e teste a conexão.',
  'db.connOk': 'Conexão OK ✓',
  'db.connFail': 'Não conectou — confira os dados.',
  'db.host': 'Host',
  'db.port': 'Porta',
  'db.user': 'Usuário',
  'db.password': 'Senha',
  'db.name': 'Banco',
  'db.test': 'Testar conexão',
  'db.testing': 'Testando…',
  'db.docker': 'Docker (docker compose up)',
  'db.dockerHint': 'Detecção pendente (o botão "Testar conexão" também detecta o Docker).',
  'db.dockerOk': 'Docker disponível ✓ — use docker compose up -d db no repositório.',
  'db.dockerMissing': 'Docker não encontrado nesta máquina.',
  'db.portable': 'Instalar PostgreSQL portátil (sem Docker) — recomendado',
  'db.portableReady': 'Pronto ✓ — localhost:',
  'db.portableHint':
      'Baixa/usa os binários oficiais + pgvector e cria um banco local do Oracle.',
  'db.install': 'Baixar e instalar agora',
  'db.installing': 'Instalando…',
  'db.installed': 'Instalado ✓',
  'embed.title': 'Embeddings',
  'embed.body':
      'O provedor que transforma memórias em vetores para a busca semântica. "Local" funciona offline e sem custo; os provedores de API têm qualidade maior.',
  'embed.provider': 'Provedor',
  'embed.local': 'Local (offline, padrão)',
  'embed.key': 'API key',
  'sec.title': 'Segurança',
  'sec.body':
      'O token protege o endpoint /hook (que lê e escreve a memória). Opcional em uso estritamente local (loopback); obrigatório se a porta for exposta.',
  'sec.none': '(sem token)',
  'sec.generate': 'Gerar token',
  'sec.remove': 'Remover',
  'inst.title': 'Instalar',
  'inst.target': 'Configuração será gravada em',
  'inst.seed': 'Restaurar backup (backups/oracle_seed.sql) se existir',
  'inst.run': 'Gravar .env + migrar banco',
  'inst.running': 'Instalando…',
  'inst.done': 'Instalado ✓',
  'agents.title': 'Conectar os agentes',
  'agents.mcp': '.mcp.json (na raiz de cada projeto do agente)',
  'agents.hooks': 'settings.json do Claude Code — bloco "hooks"',
  'agents.copy': 'Copiar',
  'agents.copied': 'Copiado.',
  'finish.title': 'Tudo pronto! 🎉',
  'finish.body':
      'O Oracle AI está instalado e migrado.\n\nPróximos passos:\n  • Abra o Oracle Studio e ative "Iniciar com o Windows" (aba Config) — ele mantém hooks, manutenção e backups na bandeja;\n  • Cole os snippets da etapa anterior nos seus agentes;\n  • A primeira sessão de agente já grava memória compartilhada.',
  // setup_state log lines
  'log.payload': 'Usando payload embutido',
  'log.cached': 'Já baixado',
  'log.downloading': 'Baixando',
  'log.downloaded': 'Baixado',
  'log.dbReady': 'Banco local pronto (sem Docker) em',
  'log.fail': 'FALHA',
  'log.envKept': '.env existente preservado em',
  'log.envWritten': '.env gravado em',
  'log.migrating': 'Criando/migrando o banco…',
  'log.migrated': 'Migrations aplicadas.',
  'log.seedRestored': 'Seed restaurado',
  'log.seedSkipped': 'Seed não restaurado',
  'log.seedMissing': 'Nenhum seed em backups/oracle_seed.sql — pulado.',
  'log.done': 'Instalação concluída.',
  'log.rows': 'linhas',
  // db cards
  'db.subtitle':
      'Onde a memória vai viver. Escolha um caminho — nos modos automáticos você não configura nada: porta, senha e banco são criados sozinhos.',
  'db.auto': 'Automático — banco embutido',
  'db.autoDesc':
      'O instalador traz o PostgreSQL + pgvector. Sem Docker, sem configuração: um clique instala, inicializa e liga o banco.',
  'db.autoBadge': 'Recomendado',
  'db.dockerCard': 'Docker',
  'db.dockerCardDesc':
      'Cria e sobe o contêiner do banco (pgvector) com um clique. Requer Docker Desktop em execução.',
  'db.dockerRun': 'Subir banco no Docker',
  'db.dockerRunning': 'Subindo contêiner…',
  'db.existingCard': 'PostgreSQL existente',
  'db.existingCardDesc':
      'Já tem um PostgreSQL 14+ rodando? Aponte para ele e teste a conexão (a extensão pgvector é criada na migração).',
  'db.ready': 'Pronto ✓',
};

const _en = <String, String>{
  'step.welcome': 'Welcome',
  'step.db': 'Database',
  'step.embed': 'Embeddings',
  'step.security': 'Security',
  'step.install': 'Install',
  'step.agents': 'Agents',
  'step.finish': 'Finish',
  'nav.back': 'Back',
  'nav.next': 'Next',
  'welcome.title': 'Welcome to Oracle AI',
  'welcome.body':
      'This wizard installs and configures the long-term memory bank for your coding agents (Claude Code, Codex, Cursor…).\n\nWhat happens next:\n  1. Database (PostgreSQL + pgvector) — use yours, Docker, or install a portable PostgreSQL with no Docker;\n  2. Embedding provider (local or API);\n  3. Hook security token;\n  4. Schema migration (and backup restore, if present);\n  5. Agent wiring (MCP + hooks).',
  'db.title': 'Database',
  'db.existing': 'Use an existing PostgreSQL',
  'db.existingHint': 'Fill in the details and test the connection.',
  'db.connOk': 'Connection OK ✓',
  'db.connFail': 'Could not connect — check the details.',
  'db.host': 'Host',
  'db.port': 'Port',
  'db.user': 'User',
  'db.password': 'Password',
  'db.name': 'Database',
  'db.test': 'Test connection',
  'db.testing': 'Testing…',
  'db.docker': 'Docker (docker compose up)',
  'db.dockerHint': 'Not probed yet (the "Test connection" button also detects Docker).',
  'db.dockerOk': 'Docker available ✓ — run docker compose up -d db in the repo.',
  'db.dockerMissing': 'Docker not found on this machine.',
  'db.portable': 'Install portable PostgreSQL (no Docker) — recommended',
  'db.portableReady': 'Ready ✓ — localhost:',
  'db.portableHint':
      'Downloads/uses the official binaries + pgvector and creates a local Oracle database.',
  'db.install': 'Download and install now',
  'db.installing': 'Installing…',
  'db.installed': 'Installed ✓',
  'embed.title': 'Embeddings',
  'embed.body':
      'The provider that turns memories into vectors for semantic search. "Local" is offline and free; API providers give higher quality.',
  'embed.provider': 'Provider',
  'embed.local': 'Local (offline, default)',
  'embed.key': 'API key',
  'sec.title': 'Security',
  'sec.body':
      'The token protects the /hook endpoint (which reads and writes memory). Optional for strictly-local (loopback) use; required once the port is exposed.',
  'sec.none': '(no token)',
  'sec.generate': 'Generate token',
  'sec.remove': 'Remove',
  'inst.title': 'Install',
  'inst.target': 'Configuration will be written to',
  'inst.seed': 'Restore backup (backups/oracle_seed.sql) if present',
  'inst.run': 'Write .env + migrate database',
  'inst.running': 'Installing…',
  'inst.done': 'Installed ✓',
  'agents.title': 'Wire your agents',
  'agents.mcp': '.mcp.json (at each agent project root)',
  'agents.hooks': 'Claude Code settings.json — "hooks" block',
  'agents.copy': 'Copy',
  'agents.copied': 'Copied.',
  'finish.title': 'All set! 🎉',
  'finish.body':
      'Oracle AI is installed and migrated.\n\nNext steps:\n  • Open Oracle Studio and enable "Start with Windows" (Settings tab) — it keeps hooks, maintenance and backups in the tray;\n  • Paste the snippets from the previous step into your agents;\n  • The first agent session already writes shared memory.',
  'log.payload': 'Using bundled payload',
  'log.cached': 'Already downloaded',
  'log.downloading': 'Downloading',
  'log.downloaded': 'Downloaded',
  'log.dbReady': 'Local database ready (no Docker) at',
  'log.fail': 'FAILED',
  'log.envKept': 'Existing .env preserved at',
  'log.envWritten': '.env written to',
  'log.migrating': 'Creating/migrating the database…',
  'log.migrated': 'Migrations applied.',
  'log.seedRestored': 'Seed restored',
  'log.seedSkipped': 'Seed not restored',
  'log.seedMissing': 'No seed at backups/oracle_seed.sql — skipped.',
  'log.done': 'Installation complete.',
  'log.rows': 'rows',
  'db.subtitle':
      'Where the memory will live. Pick a path — in the automatic modes you configure nothing: port, password and database are created for you.',
  'db.auto': 'Automatic — bundled database',
  'db.autoDesc':
      'The installer ships PostgreSQL + pgvector. No Docker, no configuration: one click installs, initializes and starts the database.',
  'db.autoBadge': 'Recommended',
  'db.dockerCard': 'Docker',
  'db.dockerCardDesc':
      'Creates and starts the database container (pgvector) in one click. Requires Docker Desktop running.',
  'db.dockerRun': 'Start database on Docker',
  'db.dockerRunning': 'Starting container…',
  'db.existingCard': 'Existing PostgreSQL',
  'db.existingCardDesc':
      'Already run PostgreSQL 14+? Point at it and test the connection (the pgvector extension is created by the migration).',
  'db.ready': 'Ready ✓',
};
