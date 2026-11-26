<script setup lang="ts">
withDefaults(
  defineProps<{
    modelValue?: boolean
    disabled?: boolean
    /** 只展示状态，不放输入框。用在已经能点击的按钮里面。 */
    decorative?: boolean
  }>(),
  {
    modelValue: false,
    disabled: false,
    decorative: false,
  },
)

const emit = defineEmits<{
  'update:modelValue': [value: boolean]
}>()

function onChange(event: Event) {
  emit('update:modelValue', (event.target as HTMLInputElement).checked)
}
</script>

<template>
  <span class="folio-check" :class="{ on: modelValue, disabled }" :aria-hidden="decorative ? 'true' : undefined">
    <input
      v-if="!decorative"
      type="checkbox"
      :checked="modelValue"
      :disabled="disabled"
      @change="onChange"
    />
    <svg viewBox="0 0 20 20" aria-hidden="true">
      <path d="M4.8 10.4 L8.6 14 L15.2 6.8" />
    </svg>
  </span>
</template>

<style scoped>
.folio-check {
  position: relative;
  width: 20px;
  height: 20px;
  flex: none;
  display: grid;
  place-items: center;
  border: 1.5px solid var(--line-strong);
  border-radius: 6px;
  background: transparent;
  transform: scale(0.86);
  transition:
    background 220ms cubic-bezier(0.34, 1.56, 0.64, 1),
    border-color 220ms cubic-bezier(0.34, 1.56, 0.64, 1),
    transform 220ms cubic-bezier(0.34, 1.56, 0.64, 1);
}

.folio-check.on {
  border-color: var(--copper, #d4a574);
  background: var(--copper, #d4a574);
  transform: scale(1);
}

.folio-check.disabled {
  opacity: 0.45;
}

.folio-check input {
  position: absolute;
  inset: 0;
  margin: 0;
  opacity: 0;
  cursor: pointer;
}

.folio-check input:disabled {
  cursor: default;
}

.folio-check:has(input:focus-visible) {
  box-shadow: 0 0 0 3px var(--copper-soft);
}

.folio-check svg {
  width: 20px;
  height: 20px;
  pointer-events: none;
}

.folio-check path {
  fill: none;
  stroke: #1a1208;
  stroke-width: 2;
  stroke-linecap: round;
  stroke-linejoin: round;
  stroke-dasharray: 16;
  stroke-dashoffset: 16;
  transition: stroke-dashoffset 220ms cubic-bezier(0.34, 1.56, 0.64, 1);
}

.folio-check.on path {
  stroke-dashoffset: 0;
}
</style>
