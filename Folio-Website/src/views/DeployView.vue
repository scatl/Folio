<template>
  <article class="wrap page">
    <header class="page-head">
      <p class="section-label">部署</p>
      <h1 class="display">跑在你自己的机器上</h1>
      <p class="lede">生产环境是一个镜像，里面有 Folio、MariaDB，以及把两者接起来的入口脚本。</p>
    </header>

    <ul class="facts">
      <li>
        <span>端口</span>
        <strong>32700</strong>
        <p>浏览器和 Android 都访问这个端口。</p>
      </li>
      <li>
        <span>数据</span>
        <strong>/data</strong>
        <p>数据库在 /data/mysql，日志在 /data/logs。挂成可写。</p>
      </li>
      <li>
        <span>片库</span>
        <strong>/media</strong>
        <p>宿主机目录映射进来。多个资料库用子目录分开。</p>
      </li>
    </ul>

    <section class="block">
      <h2>构建镜像</h2>
      <p>
        在仓库根目录运行 <code>./build-image.sh</code>，直接回车会使用版本
        <code>0.1.0</code>。下面两条命令做同样的事，标签按你的版本改。
      </p>
      <pre><code>docker build -t folio:0.1.0 .
docker save folio:0.1.0 -o .build/folio-0.1.0.tar</code></pre>
      <p class="note">导出的 tar 在 <code>.build</code> 目录，文件名带版本号。</p>
    </section>

    <section class="block">
      <h2>在群晖里启动</h2>
      <ol class="steps">
        <li>
          <span class="num">01</span>
          <div>
            <h3>导入映像</h3>
            <p>Docker → 映像 → 新增，选择 <code>folio-*.tar</code>。</p>
          </div>
        </li>
        <li>
          <span class="num">02</span>
          <div>
            <h3>映射端口和目录</h3>
            <p>
              主机 <code>32700</code> 到容器 <code>32700</code>。数据目录挂到 <code>/data</code>（读写），片库挂到
              <code>/media</code>。多个片库放在子目录，例如 <code>/media/movies</code>、<code>/media/tv</code>。
            </p>
          </div>
        </li>
        <li>
          <span class="num">03</span>
          <div>
            <h3>改掉数据库密码</h3>
            <p>
              至少修改 <code>MYSQL_PASSWORD</code>。<code>MYSQL_ROOT_PASSWORD</code> 默认与它相同。
              <code>/data/mysql</code> 一旦初始化，再改这些变量不会改掉已经建好的账号。
            </p>
          </div>
        </li>
        <li>
          <span class="num">04</span>
          <div>
            <h3>填写 TMDB</h3>
            <p>浏览器打开 <code>http://&lt;群晖 IP&gt;:32700</code>。登录后进入设置，填上 TMDB API Key。不填就无法刮削。</p>
          </div>
        </li>
      </ol>
    </section>

    <section class="block">
      <h2>第一次打开</h2>
      <p>键写在数据库里，不在仓库里。下面是出厂值，够把墙跑起来。</p>
      <dl class="spec">
        <div>
          <dt>TMDB API Key</dt>
          <dd>必填。海报、简介、演职员、类型和季集都从这里来。</dd>
        </div>
        <div>
          <dt>详情语言</dt>
          <dd>默认 zh-CN，决定写入的文案。</dd>
        </div>
        <div>
          <dt>搜索语言</dt>
          <dd>默认 en-US，用来按文件名检索。</dd>
        </div>
        <div>
          <dt>自动匹配</dt>
          <dd>阈值默认 0.72。达到就直接入库，否则留在任务里人工选。</dd>
        </div>
        <div>
          <dt>扫描</dt>
          <dd>默认每 10 分钟，只处理新文件或内容变过的文件。目录监听默认开着。</dd>
        </div>
        <div>
          <dt>OMDb / TVDB</dt>
          <dd>可以先不填。不填不影响 TMDB 匹配。</dd>
        </div>
      </dl>
    </section>

    <section class="block">
      <h2>本机开发</h2>
      <p>
        前端在 <code>Folio-Web</code>：<code>npm install</code> 然后 <code>npm run dev</code>，地址
        <code>http://127.0.0.1:5173</code>，<code>/api</code> 代理到 32700。
      </p>
      <p>
        后端需要 JDK 25。在 <code>Folio-Server</code> 执行 <code>.\gradlew.bat :app:bootRun</code>。本机没有容器里的
        MariaDB 入口脚本，数据库用你自己的 MySQL。片库目录同样只认 <code>/media</code>；Windows 上可以把片库联接到当前盘的
        <code>\media</code>，例如 <code>C:\media</code>。
      </p>
      <p class="note">环境变量和刮削选项的完整说明在仓库根目录 README。</p>
    </section>
  </article>
</template>

<style scoped>
.page {
  padding-bottom: clamp(3.25rem, 8vw, 5rem);
}

.page-head {
  padding-top: clamp(2.5rem, 6vw, 4.25rem);
}

.facts {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 0.8rem;
  margin: 2rem 0 0;
  padding: 0;
  list-style: none;
}

.facts li {
  padding: 1.1rem 1.15rem 1.15rem;
  border: 1px solid var(--line);
  border-radius: 16px;
  background: rgba(20, 24, 32, 0.72);
}

.facts span {
  color: var(--teal);
  font-size: 0.8rem;
  font-weight: 700;
}

.facts strong {
  display: block;
  margin: 0.3rem 0 0.4rem;
  font-family: var(--font-display);
  font-size: clamp(1.7rem, 3vw, 2rem);
  font-weight: 700;
  letter-spacing: -0.03em;
  line-height: 1.1;
}

.facts p,
.block p {
  margin: 0;
  color: var(--ink-soft);
  line-height: 1.7;
}

.facts p {
  color: var(--ink-muted);
  font-size: 0.92rem;
}

.block {
  padding-top: 2.75rem;
}

.block h2 {
  margin: 0 0 0.75rem;
  font-size: 1.35rem;
}

.block p + p,
.note,
pre {
  margin-top: 0.85rem;
}

.note {
  color: var(--ink-muted);
  font-size: 0.92rem;
}

pre {
  margin-bottom: 0;
  padding: 0.95rem 1.05rem;
  overflow-x: auto;
  border: 1px solid var(--line);
  border-radius: 12px;
  background: #0b0d12;
  font-family: var(--mono);
  font-size: 0.88rem;
  line-height: 1.65;
}

pre code {
  color: var(--ink);
}

.steps,
.spec {
  margin: 0.35rem 0 0;
  padding: 0;
}

.steps {
  list-style: none;
}

.steps li,
.spec div {
  display: grid;
  grid-template-columns: 2.75rem minmax(0, 1fr);
  gap: 0.35rem 0.9rem;
  padding: 1.05rem 0;
  border-top: 1px solid var(--line);
}

.steps li:last-child,
.spec div:last-child {
  border-bottom: 1px solid var(--line);
}

.num {
  font-family: var(--font-display);
  color: var(--copper);
  font-weight: 700;
  letter-spacing: -0.03em;
}

.steps h3,
.spec dt {
  margin: 0;
  font-size: 1rem;
  font-weight: 700;
}

.steps p,
.spec dd {
  margin: 0.28rem 0 0;
}

.spec div {
  grid-template-columns: 9.5rem minmax(0, 1fr);
  gap: 0.35rem 1.5rem;
}

.spec dd {
  margin: 0;
  color: var(--ink-soft);
  line-height: 1.65;
}

@media (max-width: 800px) {
  .facts {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 640px) {
  .spec div {
    grid-template-columns: 1fr;
    gap: 0.25rem;
  }
}
</style>
