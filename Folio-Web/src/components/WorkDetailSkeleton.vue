<template>
  <div class="detail-skel" aria-busy="true" aria-label="正在加载详情">
    <div class="hero">
      <div class="hero-shade" />
      <div class="hero-inner">
        <div class="back shimmer" />
        <div class="hero-body">
          <div class="poster shimmer" />
          <div class="copy">
            <div class="line eyebrow shimmer" />
            <div class="line title shimmer" />
            <div class="line sub shimmer" />
            <div class="line tag shimmer" />
            <div class="chips">
              <span class="chip shimmer" />
              <span class="chip shimmer" />
              <span class="chip shimmer" />
              <span class="chip shimmer" />
            </div>
          </div>
        </div>
      </div>
    </div>

    <div class="body">
      <section class="block">
        <div class="heading shimmer" />
        <div class="para shimmer" />
        <div class="para mid shimmer" />
        <div class="para short shimmer" />
      </section>
      <section class="block">
        <div class="heading shimmer" />
        <div class="facts">
          <div v-for="n in 8" :key="n" class="fact">
            <div class="fact-label shimmer" />
            <div class="fact-value shimmer" />
          </div>
        </div>
      </section>
      <section class="block">
        <div class="heading shimmer" />
        <div class="people">
          <div v-for="n in 8" :key="n" class="person">
            <div class="avatar shimmer" />
            <div class="person-line shimmer" />
            <div class="person-line short shimmer" />
          </div>
        </div>
      </section>
    </div>
  </div>
</template>

<style scoped>
.detail-skel {
  min-height: 100vh;
  animation: fade-in 0.4s ease both;
}

.hero {
  position: relative;
  min-height: min(72vh, 640px);
  background-color: transparent;
}

.hero-shade {
  position: absolute;
  inset: 0;
  background:
    linear-gradient(180deg, rgba(10, 12, 16, 0.2) 0%, rgba(10, 12, 16, 0.45) 55%, transparent 100%),
    linear-gradient(90deg, rgba(10, 12, 16, 0.25) 0%, transparent 55%);
}

.hero-inner {
  position: relative;
  z-index: 1;
  width: min(1100px, calc(100% - 2.5rem));
  margin: 0 auto;
  padding: 1.5rem 0 2.5rem;
  min-height: inherit;
  display: flex;
  flex-direction: column;
}

.back {
  width: 8.5rem;
  height: 2.4rem;
  border-radius: 999px;
  margin-bottom: 2rem;
}

.hero-body {
  margin-top: auto;
  display: grid;
  grid-template-columns: 200px 1fr;
  gap: 1.75rem;
  align-items: end;
}

.poster {
  width: 200px;
  aspect-ratio: 2 / 3;
  border-radius: 12px;
  border: 1px solid var(--line);
}

.copy {
  display: grid;
  gap: 0.7rem;
  padding-bottom: 0.35rem;
}

.line {
  height: 0.9rem;
  border-radius: 999px;
}

.line.eyebrow {
  width: 7rem;
  height: 0.7rem;
}

.line.title {
  width: min(18rem, 70%);
  height: 2.4rem;
  border-radius: 12px;
}

.line.sub {
  width: 8rem;
}

.line.tag {
  width: min(22rem, 80%);
  height: 0.85rem;
}

.chips {
  display: flex;
  flex-wrap: wrap;
  gap: 0.45rem;
  margin-top: 0.35rem;
}

.chip {
  width: 4.5rem;
  height: 1.55rem;
  border-radius: 999px;
}

.body {
  width: min(1100px, calc(100% - 2.5rem));
  margin: 0 auto;
  padding: 0.5rem 0 4rem;
  display: grid;
  gap: 2.25rem;
}

.block {
  display: grid;
  gap: 0.75rem;
}

.heading {
  width: 4.5rem;
  height: 0.85rem;
  border-radius: 999px;
}

.para {
  height: 0.85rem;
  border-radius: 999px;
  width: 100%;
  max-width: 48rem;
}

.para.mid {
  width: 86%;
}

.para.short {
  width: 62%;
}

.facts {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
  gap: 0.85rem 1rem;
}

.fact {
  display: grid;
  gap: 0.4rem;
  padding-bottom: 0.7rem;
  border-bottom: 1px solid var(--line);
}

.fact-label {
  width: 3.2rem;
  height: 0.55rem;
  border-radius: 999px;
}

.fact-value {
  width: 70%;
  height: 0.8rem;
  border-radius: 999px;
}

.people {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(112px, 1fr));
  gap: 1.1rem 0.75rem;
}

.person {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.45rem;
}

.avatar {
  width: 72px;
  height: 72px;
  border-radius: 50%;
}

.person-line {
  width: 4.5rem;
  height: 0.65rem;
  border-radius: 999px;
}

.person-line.short {
  width: 3rem;
  height: 0.55rem;
}

@keyframes fade-in {
  from {
    opacity: 0;
  }
  to {
    opacity: 1;
  }
}

@media (max-width: 720px) {
  .hero-inner,
  .body {
    width: min(100% - 1.1rem, 1100px);
  }

  .hero-inner {
    padding-top: calc(0.9rem + var(--safe-top));
  }

  .hero-body {
    grid-template-columns: 108px minmax(0, 1fr);
    gap: 0.9rem;
  }

  .poster {
    width: 108px;
  }

  .line.title {
    height: 1.8rem;
  }
}

@media (prefers-reduced-motion: reduce) {
  .detail-skel {
    animation: none;
  }
}
</style>
