// §AI-control: keeper общего браузера (на официальном MCP-SDK).
//
// @playwright/mcp поднимает Chromium ЛЕНИВО (на первый вызов инструмента) и
// ЗАКРЫВАЕТ его, когда отключается последний клиент. Чтобы общий браузер был
// виден во Viewer ВСЕГДА (даже без активного агента) и юзер мог сам листать —
// держим одну персистентную MCP-сессию.
//
// Ключевое: сессию держит официальный @modelcontextprotocol/sdk (транспорт
// Streamable-HTTP удерживает SSE-поток) — в отличие от самописного POST-клиента,
// который mcp считал «отключившимся» и закрывал браузер. Пока SDK-клиент
// подключён, браузер жив.
//
// Благодаря --shared-browser-context агент, подключаясь позже, попадает в ТОТ ЖЕ
// браузер/контекст (один user-data-dir) → рулит тем же окном, что видит юзер.

const { Client } = require('@modelcontextprotocol/sdk/client/index.js');
const { StreamableHTTPClientTransport } = require('@modelcontextprotocol/sdk/client/streamableHttp.js');

const PORT = process.env.PW_MCP_PORT || '9250';
const ENDPOINT = `http://127.0.0.1:${PORT}/mcp`;
const START_URL = process.env.PW_MCP_START_URL || 'about:blank';

const sleep = ms => new Promise(r => setTimeout(r, ms));
let reconnecting = false;

function scheduleReconnect(why) {
  if (reconnecting) return;
  reconnecting = true;
  console.log('keeper: сессия закрыта —', why, '→ переподключение через 3с');
  setTimeout(() => { reconnecting = false; run(); }, 3000);
}

async function run() {
  const transport = new StreamableHTTPClientTransport(new URL(ENDPOINT));
  const client = new Client({ name: 'browser-keeper', version: '1' }, { capabilities: {} });
  transport.onerror = e => console.log('keeper: transport error —', (e && e.message) || e);
  transport.onclose = () => scheduleReconnect('onclose');
  try {
    await client.connect(transport);
    // Навигация поднимает окно браузера на :99. Делаем на КАЖДЫЙ (пере)коннект:
    // переподключение случается по сути только при рестарте mcp, когда браузер
    // и так закрыт — значит его надо открыть заново.
    await client.callTool({ name: 'browser_navigate', arguments: { url: START_URL } });
    console.log('keeper: подключён, общий браузер открыт на', START_URL);
    // Клиент остаётся подключённым (транспорт держит SSE) → браузер жив. Процесс
    // не завершается, пока открыт транспорт; для надёжности держим таймер.
  } catch (e) {
    console.log('keeper: ошибка коннекта/навигации —', (e && e.message) || e);
    try { await client.close(); } catch (_) {}
    scheduleReconnect('connect-failed');
  }
}

// пока mcp не поднялся — повторяем; далее держим процесс живым
setInterval(() => {}, 1 << 30);
(async () => {
  for (;;) {
    try { await run(); break; }
    catch (e) { await sleep(3000); }
  }
})();
