<script setup lang="ts">
import { RouterLink } from 'vue-router'

const points = [
  { title: '海报墙', body: '电影和剧集按资料库浏览。' },
  { title: '继续观看', body: '从上次停下的地方接着播。' },
  { title: '想看', body: '先标上，有空再看。' },
  { title: '播放列表', body: '把要连着看的放在一起。' },
  { title: '搜索', body: '按片名、类型或演职员找。' },
  { title: '详情', body: '介绍、演职员和分集在同一页。' },
  { title: '播放', body: '在浏览器里直接看。' },
  { title: '刮削', body: '自动补上海报和简介。' },
  { title: 'Android', body: '手机连同一台服务器。' },
]
</script>

<template>
  <div class="wrap">
    <section class="hero">
      <div class="hero-copy">
        <p class="section-label">自托管</p>
        <h1 class="display">自己的片库，<br />一面海报墙</h1>
        <p class="lede">
          Folio 扫描你挂进来的视频目录，向 TMDB 要海报、简介和季集，然后在浏览器里播放。服务和数据库在同一个镜像里。
        </p>
        <div class="actions">
          <RouterLink class="btn btn-primary" :to="{ name: 'deploy' }">如何部署</RouterLink>
          <RouterLink :to="{ name: 'home', hash: '#product' }" custom v-slot="{ href, navigate }">
            <a class="btn btn-ghost" :href="href" @click="navigate">看它做什么</a>
          </RouterLink>
        </div>
      </div>
      <figure class="hero-shot">
        <img src="/screens/folio-home.jpg" alt="Folio 网页端首页，有资料库、继续观看和近期作品" />
      </figure>
    </section>

    <section id="product" class="band">
      <p class="section-label">产品</p>
      <h2 class="subhead">功能</h2>
      <ol class="caps">
        <li v-for="item in points" :key="item.title">
          <h3>{{ item.title }}</h3>
          <p>{{ item.body }}</p>
        </li>
      </ol>
      <div class="gallery">
        <figure>
          <img src="/screens/folio-library.jpg" alt="电影资料库的海报墙" />
          <figcaption>资料库</figcaption>
        </figure>
        <figure>
          <img src="/screens/folio-detail.jpg" alt="作品详情页，可以播放" />
          <figcaption>作品详情</figcaption>
        </figure>
      </div>
    </section>

    <section class="band close">
      <div class="next">
        <div>
          <p class="section-label">部署</p>
          <h2 class="subhead">一个镜像就能跑</h2>
          <p>适合群晖，也适合任何能跑 Docker 的主机。端口 32700，数据在 /data，片库挂到 /media。</p>
        </div>
        <RouterLink class="btn btn-primary" :to="{ name: 'deploy' }">查看步骤</RouterLink>
      </div>
    </section>
  </div>
</template>

<style scoped>
.hero {
  padding: clamp(2.5rem, 6vw, 4.25rem) 0 0.25rem;
}

.hero-copy {
  max-width: 40rem;
}

.actions {
  display: flex;
  flex-wrap: wrap;
  gap: 0.7rem;
  margin-top: 1.6rem;
}

.hero-shot {
  margin: 2.25rem 0 0;
}

.hero-shot img,
.gallery img {
  width: 100%;
  border: 1px solid var(--line);
  border-radius: 16px;
  box-shadow: 0 28px 70px rgba(0, 0, 0, 0.38);
}

.gallery {
  display: grid;
  gap: 1.35rem;
  margin-top: 1.75rem;
}

.gallery figure {
  margin: 0;
}

.gallery figcaption {
  margin-top: 0.5rem;
  color: var(--ink-muted);
  font-size: 0.82rem;
}

.band {
  padding: clamp(2rem, 5vw, 3.25rem) 0;
}

.caps {
  list-style: none;
  margin: 1.35rem 0 0;
  padding: 0;
}

.caps li {
  display: grid;
  grid-template-columns: 7.5rem minmax(0, 1fr);
  gap: 0.4rem 1.75rem;
  padding: 1.25rem 0;
  border-top: 1px solid var(--line);
}

.caps li:last-child {
  border-bottom: 1px solid var(--line);
}

.caps h3 {
  margin: 0;
  font-size: 1.05rem;
}

.caps p {
  margin: 0;
  max-width: 40rem;
  color: var(--ink-soft);
  line-height: 1.7;
}

.close {
  padding-top: 0.5rem;
  padding-bottom: clamp(3rem, 7vw, 4.5rem);
}

.next {
  display: flex;
  align-items: end;
  justify-content: space-between;
  gap: 1.5rem 2rem;
  padding: clamp(1.35rem, 3vw, 1.85rem);
  border: 1px solid var(--line);
  border-radius: 18px;
  background: rgba(20, 24, 32, 0.72);
}

.next p:last-child {
  margin: 0.7rem 0 0;
  max-width: 36rem;
  color: var(--ink-soft);
  line-height: 1.7;
}

@media (max-width: 800px) {
  .hero {
    padding-top: 2.25rem;
  }
}

@media (max-width: 640px) {
  .caps li,
  .next {
    grid-template-columns: 1fr;
    display: grid;
    align-items: start;
  }

  .next {
    justify-items: start;
  }
}
</style>
