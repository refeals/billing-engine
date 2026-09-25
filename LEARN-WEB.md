# Learning Vue through this project (the web app)

A guide to `web/` for a React developer. It explains how the back-office works **and** the
Vue concepts behind it, always with code from this repository, comparing with React
wherever the comparison helps (and warning where it misleads).

Read it with the code open. Every path is relative to `web/`.

Companion: [LEARN-API.md](LEARN-API.md) for the Rails side.

## Contents

1. [The mental map](#1-the-mental-map)
2. [The one idea that changes everything: setup runs once](#2-the-one-idea-that-changes-everything-setup-runs-once)
3. [Single-File Components](#3-single-file-components)
4. [Reactivity: `ref`, `reactive`, `computed`, `watch`](#4-reactivity-ref-reactive-computed-watch)
5. [Templates](#5-templates)
6. [Component communication: props, emits, `v-model`, slots](#6-component-communication-props-emits-v-model-slots)
7. [Lifecycle and template refs](#7-lifecycle-and-template-refs)
8. [Composables: Vue's custom hooks](#8-composables-vues-custom-hooks)
9. [Pinia: global state](#9-pinia-global-state)
10. [Vue Router](#10-vue-router)
11. [Talking to the API](#11-talking-to-the-api)
12. [How the app boots and how login works](#12-how-the-app-boots-and-how-login-works)
13. [Styling with Tailwind v4](#13-styling-with-tailwind-v4)
14. [TypeScript with Vue](#14-typescript-with-vue)
15. [Testing with Vitest, Vue Test Utils and Playwright](#15-testing-with-vitest-vue-test-utils-and-playwright)
16. [Tooling](#16-tooling)
17. [Gotchas for React developers](#17-gotchas-for-react-developers)
18. [Exercises](#18-exercises)
19. [Where to go next](#19-where-to-go-next)

## 1. The mental map

| React | Vue 3 (Composition API) | In this project |
|---|---|---|
| function component + JSX | Single-File Component (`.vue`): `<script setup>` + `<template>` | every file in `src/components`, `src/features` |
| `useState` | `ref()` / `reactive()` | everywhere |
| `useMemo` | `computed()` (dependencies tracked automatically) | `SubscriptionsView.vue` |
| `useEffect` | `watch()` / `watchEffect()` / lifecycle hooks | `BaseDialog.vue` |
| `useEffect(() => ..., [])` | `onMounted()` | `ClockWidget.vue` |
| cleanup function of an effect | `onBeforeUnmount()` / `onUnmounted()` | `SubscriptionsView.vue` |
| `useRef` (DOM) | `useTemplateRef()` + `ref="name"` | `BaseDialog.vue` |
| `useCallback` | not needed | — |
| props | `defineProps<T>()` | all components |
| callback props (`onCreated`) | `defineEmits` + `emit('created')` | `CustomerFormDialog.vue` |
| controlled input (`value` + `onChange`) | `v-model` | forms |
| `value` + `onChange` pair on your own component | `defineModel()` + `v-model:open` | dialogs |
| `children` / render props | slots (`<slot />`, named slots) | `BaseDialog`, `ProviderOutbox` |
| custom hook | composable (`useSomething()`) | `src/composables/` |
| Context / Zustand / Redux | Pinia store | `src/stores/clock.ts`, `auth.ts` |
| React Router | Vue Router | `src/router/` |
| `{cond && <X/>}` | `v-if` | everywhere |
| `items.map(i => <X key/>)` | `v-for` + `:key` | lists |
| `className` / `clsx` | `class` + `:class` binding | badges |
| Jest + React Testing Library | Vitest + Vue Test Utils | `__tests__/` folders |
| CRA / Vite React | Vite + `@vitejs/plugin-vue` | `vite.config.ts` |

## 2. The one idea that changes everything: setup runs once

In React, your component **function runs on every render**. That is why you need
`useState` to remember values between calls, `useCallback`/`useMemo` to keep identities
stable, dependency arrays, and why stale closures exist.

In Vue, `<script setup>` **runs once**, when the component is created. It builds reactive
state and functions, and returns them to the template. After that, only the **template**
re-renders when the reactive values it reads change.

```vue
<script setup lang="ts">
import { ref } from 'vue'

const count = ref(0)          // created once, lives as long as the component
function increment() {        // created once: no useCallback needed
  count.value++               // mutate: Vue notices and re-renders what reads `count`
}
</script>

<template>
  <button @click="increment">Clicked {{ count }} times</button>
</template>
```

Consequences you will feel immediately:

- **No dependency arrays.** Vue tracks which reactive values a `computed` or `watch` reads,
  automatically.
- **No stale closures.** A function always reads the current `.value`.
- **No rules of hooks.** You can call composables in conditions or loops (inside setup).
  You still call them during setup, not later in an event handler.
- **Mutation is the API.** You don't `setX(newX)`; you assign `x.value = newX` or push into a
  reactive array. Vue's reactivity is built on JavaScript Proxies that intercept those
  writes.

## 3. Single-File Components

A `.vue` file has up to three blocks:

```vue
<script setup lang="ts">
// logic: imports, state, functions. Everything declared here is usable in the template.
</script>

<template>
  <!-- HTML with Vue directives. One root element or several, both work. -->
</template>

<style scoped>
/* optional; this project uses Tailwind classes instead */
</style>
```

`<script setup>` is compiler sugar: imported components are usable in the template without
registration, top-level variables and functions are exposed to the template, and macros
like `defineProps` and `defineEmits` don't need imports.

Look at `src/components/StatusBadge.vue` for the smallest real example: props in, markup
out.

## 4. Reactivity: `ref`, `reactive`, `computed`, `watch`

### `ref`: one reactive value

```ts
const pending = ref(false)       // Ref<boolean>
pending.value = true             // in <script>: read and write through .value
```

```vue
<BaseButton :disabled="pending">  <!-- in <template>: no .value, refs are unwrapped -->
```

### `reactive`: a reactive object

```ts
// src/features/customers/CustomerFormDialog.vue
const form = reactive({ name: '', email: '' })
form.name = 'Studio Flow'          // no .value; the object itself is reactive
Object.assign(form, { name: '', email: '' })   // reset every field
```

Rule of thumb used here: `ref` for single values and anything you replace wholesale,
`reactive` for form objects whose fields you mutate.

### `computed`: derived state (useMemo without the array)

```ts
// src/features/subscriptions/SubscriptionsView.vue
const status = computed(() => (typeof route.query.status === 'string' ? route.query.status : ''))
const subscriptions = computed(() => data.value?.data ?? [])
const hasFilters = computed(() => status.value !== '' || query.value !== '')
```

Cached, recomputed only when something it read changes. Read it with `.value` in script.

### `watch`: side effects when something changes (useEffect-ish)

```ts
// debounce the search box into the URL
watch(search, (value) => {
  clearTimeout(debounce)
  debounce = setTimeout(() => {
    router.replace({ query: { ...route.query, q: value.trim() || undefined, page: undefined } })
  }, 300)
})
```

```ts
// src/components/BaseDialog.vue: keep the native <dialog> in sync with the `open` model
watch(open, sync)
```

Differences from `useEffect`:

- A `watch` does **not** run on mount by default (pass `{ immediate: true }` for that).
  Mount-time work goes in `onMounted`.
- You watch a ref, a getter (`() => route.query`), or an array of them.
- It gives you `(newValue, oldValue)`.
- `watchEffect(fn)` runs immediately and re-runs whenever anything it read changes
  (closer to `useEffect` with automatic dependencies).

### `shallowRef`

`src/composables/useAsyncData.ts` stores API responses in `shallowRef`: only replacing
`.value` triggers updates, not mutating deep inside. Cheaper for big JSON you never mutate.

## 5. Templates

Templates are HTML plus **directives** (attributes starting with `v-`), compiled to render
functions at build time.

| Syntax | Meaning | React equivalent |
|---|---|---|
| `{{ expression }}` | text interpolation | `{expression}` |
| `:title="expr"` (short for `v-bind:title`) | bind an attribute or prop to JS | `title={expr}` |
| `@click="handler"` (short for `v-on:click`) | listen to an event | `onClick={handler}` |
| `@submit.prevent="submit"` | event with modifier | `onSubmit={e => { e.preventDefault(); submit() }}` |
| `v-if` / `v-else-if` / `v-else` | conditional rendering | `cond ? <A/> : <B/>` |
| `v-show` | toggle `display: none` only | style toggle |
| `v-for="item in items" :key="item.id"` | lists | `items.map(item => <X key={item.id}/>)` |
| `v-model="form.email"` | two-way binding | `value` + `onChange` |
| `:class="{ 'text-danger': hasError }"` or an array | conditional classes | `clsx(...)` |

A real snippet with most of them (`src/features/dashboard/DashboardView.vue`):

```vue
<li v-for="status in SUBSCRIPTION_STATUSES" :key="status">
  <RouterLink :to="{ name: 'subscriptions', query: { status } }" class="grid ...">
    <StatusBadge :status="status" />
    <span
      class="block h-full rounded-full bg-accent"
      :style="{ width: `${shareOf(summary.subscriptions_by_status[status], totalSubscriptions)}%` }"
    />
    <span class="text-right tabular-nums">{{ summary.subscriptions_by_status[status] }}</span>
  </RouterLink>
</li>
```

Note: plain `class` and bound `:class` merge; plain attributes (`class="..."`) are strings,
bound ones (`:status="status"`) are JavaScript.

## 6. Component communication: props, emits, `v-model`, slots

### Props

```ts
// src/components/StatusBadge.vue
defineProps<{ status: SubscriptionStatus }>()

// src/components/ConfirmDialog.vue: defaults with withDefaults
withDefaults(
  defineProps<{ title: string; confirmLabel: string; pending?: boolean; variant?: 'primary' | 'danger' }>(),
  { pending: false, variant: 'danger' },
)
```

Props are **read-only** in the child (Vue warns if you assign them), same as React.
In templates, pass them with `:` for JS values: `<ConfirmDialog title="Reset?" :pending="resetPending" />`.
Prop names are camelCase in script and usually kebab-case in templates
(`confirmLabel` ↔ `confirm-label`); both work.

### Emits: events instead of callback props

```ts
// src/features/customers/CustomerFormDialog.vue
const emit = defineEmits<{ created: [customer: CustomerDetail] }>()
// ...
emit('created', customer)
```

The parent listens like a DOM event:

```vue
<CustomerFormDialog v-model:open="creating" @created="onCreated" />
```

React: `<CustomerFormDialog onCreated={onCreated} />`. Vue separates "data in" (props) from
"events out" (emits).

### `v-model` on your own components: `defineModel`

`v-model` is sugar for "a prop plus an update event". On a component:

```ts
// src/components/BaseDialog.vue
const open = defineModel<boolean>('open', { required: true })
// reading open.value reads the parent's value; writing open.value = false emits
// 'update:open', which updates the parent's ref
```

```vue
<!-- parent -->
<BaseDialog v-model:open="resetOpen" title="Reset demo data?">
```

React equivalent: `<BaseDialog open={resetOpen} onOpenChange={setResetOpen} />`. Every
dialog in this project is controlled this way; the dialog closes itself with
`open.value = false` (e.g. on Esc via the native `close` event).

### Slots: children and render props

Default slot, like `children`:

```vue
<!-- src/components/BaseDialog.vue -->
<div v-if="open" class="p-5">
  <h2 class="mb-4 text-base font-semibold">{{ title }}</h2>
  <slot />
</div>
```

Named slots, like passing several JSX props (`heading={<h2>…</h2>}`):

```vue
<!-- src/features/simulator/ProviderOutbox.vue -->
<div><slot name="heading" /></div>

<!-- src/features/simulator/ScenarioRunPanel.vue -->
<ProviderOutbox :scenario-run-id="run.id">
  <template #heading>
    <h3 class="text-sm font-semibold">Events this run made the provider send</h3>
  </template>
</ProviderOutbox>
```

Slots can also pass data back up (scoped slots, `<slot :item="item" />` then
`<template #default="{ item }">`), which is Vue's version of render props.

### Exposing methods: `defineExpose`

Components are closed by default. `ProviderOutbox.vue` exposes one method so the Scenario
Lab can ask it to jump back to page 1:

```ts
defineExpose({ showFirstPage })
```

```ts
// ScenarioLabView.vue
const outbox = useTemplateRef('outbox')       // <ProviderOutbox ref="outbox">
outbox.value?.showFirstPage()
```

React equivalent: `forwardRef` + `useImperativeHandle`. Use sparingly; props and events are
the normal path.

## 7. Lifecycle and template refs

```ts
onMounted(clock.load)                      // ClockWidget.vue: after the first render
onBeforeUnmount(() => clearTimeout(debounce))   // SubscriptionsView.vue: cleanup
```

Template refs give you the DOM element:

```ts
// src/components/BaseDialog.vue
const dialog = useTemplateRef<HTMLDialogElement>('dialog')

function sync(isOpen: boolean) {
  if (!dialog.value) return
  if (isOpen && !dialog.value.open) dialog.value.showModal()
  if (!isOpen && dialog.value.open) dialog.value.close()
}
```

```vue
<dialog ref="dialog" @close="open = false">
```

`useTemplateRef('dialog')` ↔ `ref="dialog"` in the template, like `useRef` +
`ref={dialogRef}`. It is `null` until mounted.

## 8. Composables: Vue's custom hooks

A composable is a function that uses Vue's reactivity and lifecycle APIs and returns
reactive state. Same idea as a custom hook, fewer rules.

### `useAsyncData`: loading/error/data for one request

```ts
// src/composables/useAsyncData.ts
export function useAsyncData<T>(loader: () => Promise<T>) {
  const data = shallowRef<T | null>(null)
  const error = ref<ApiError | null>(null)
  const loading = ref(false)
  let latestRequest = 0

  async function reload() {
    const request = ++latestRequest
    loading.value = true
    error.value = null
    try {
      const result = await loader()
      if (request === latestRequest) data.value = result   // ignore stale responses
    } catch (caught) {
      if (request === latestRequest) error.value = toApiError(caught)
    } finally {
      if (request === latestRequest) loading.value = false
    }
  }

  return { data, error, loading, reload }
}
```

Used by nearly every screen:

```ts
const { data, error, loading, reload } = useAsyncData(() =>
  fetchSubscriptions({ status: status.value, q: query.value, page: page.value }),
)
```

The `loader` reads `status.value` etc. **when it runs**, so `reload()` always fetches with
the current filters: no dependency array, no stale closure. The `latestRequest` counter
solves the classic race (a slow response for old filters overwriting a newer one), which
React Query would do for you in React. Vue has libraries for this too (TanStack Query for
Vue, Pinia Colada); this project keeps a 30-line version to show the idea.

### `useClockRefresh`: react to simulated time

```ts
// src/composables/useClockRefresh.ts
export function useClockRefresh(loader: () => unknown) {
  const clock = useClockStore()
  onMounted(loader)
  watch(() => clock.revision, loader)
}
```

Moving the simulated clock can renew, charge or cancel anything, so every screen calls
`useClockRefresh(reload)`: load on mount, reload whenever the clock store's `revision`
changes. A composable can register lifecycle hooks for the component that calls it, which
is what makes this a one-liner in each view.

## 9. Pinia: global state

Pinia is Vue's official store. The "setup store" style used here looks exactly like a
composable, wrapped in `defineStore`:

```ts
// src/stores/clock.ts (trimmed)
export const useClockStore = defineStore('clock', () => {
  const now = ref<string | null>(null)
  const pending = ref(false)
  const revision = ref(0)       // bumped whenever simulated time changes

  async function advance(days: number) {
    const result = await track(() => advanceClock(days))
    if (!result) return
    now.value = result.now
    revision.value += 1
  }

  return { now, pending, revision, load, advance, reset, timeMoved }
})
```

- Every component that calls `useClockStore()` gets the **same** instance (a singleton per
  app), like a Zustand store.
- Read state directly: `clock.now`, `clock.pending` (refs are unwrapped on the store object).
- Actions are plain functions: `clock.advance(3)`.
- Don't destructure state (`const { now } = useClockStore()` loses reactivity); use
  `storeToRefs(store)` if you want to.

Stores here: `clock` (simulated date, the header buttons, the `revision` every screen
watches) and `auth` (the signed-in user, `load/signIn/signOut`).

## 10. Vue Router

```ts
// src/router/index.ts (trimmed)
const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    { path: '/login', name: 'login', component: () => import('@/features/auth/LoginView.vue'),
      meta: { title: 'Sign in', public: true } },
    { path: '/subscriptions/:id', name: 'subscription',
      component: () => import('@/features/subscriptions/SubscriptionDetailView.vue'),
      meta: { title: 'Subscription' } },
    // ...
  ],
})
```

- `component: () => import(...)` lazy-loads each screen (code splitting), like
  `React.lazy`.
- `meta` is free-form data per route; the layout reads `meta.title` for the page header, the
  auth guard reads `meta.public`.
- `<RouterView />` renders the matched route (≈ `<Outlet />`); `<RouterLink :to="...">`
  renders a link (≈ `<Link>`). `:to` accepts a path or `{ name, params, query }`.
- In script: `useRoute()` (current location, reactive) and `useRouter()` (navigation:
  `push`, `replace`).

### The URL as state

List filters live in the query string, so a filtered list can be bookmarked or shared:

```ts
// src/features/subscriptions/SubscriptionsView.vue
const status = computed(() => (typeof route.query.status === 'string' ? route.query.status : ''))

function setStatus(value: string) {
  router.replace({ query: { ...route.query, status: value || undefined, page: undefined } })
}

watch(() => route.query, () => { if (route.name === 'subscriptions') reload() })
```

Changing a filter changes the URL; the URL change triggers the reload. One source of
truth, like `useSearchParams` in React Router.

### Navigation guards

```ts
router.beforeEach(async (to) => {
  const auth = useAuthStore()
  await auth.load()
  if (!to.meta.public && auth.status !== 'signed_in') {
    return { name: 'login', query: { redirect: to.fullPath } }
  }
  if (to.name === 'login' && auth.status === 'signed_in') return { name: 'dashboard' }
})
```

A guard runs before every navigation and can redirect by returning a location. React Router
does this with loaders or a wrapper component; in Vue it is built in.

## 11. Talking to the API

Everything HTTP lives in `src/api/`, one module per resource, with TypeScript types that
mirror the Rails serializers field by field (`snake_case` kept on purpose).

```ts
// src/api/client.ts (trimmed)
export async function apiRequest<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const response = await fetch(`${baseUrl}${path}`, {
    method: options.method ?? 'GET',
    headers: { Accept: 'application/json', ... },
    body: hasBody ? JSON.stringify(options.body) : undefined,
    credentials: 'include',           // send the session cookie (see LEARN-API §13)
  })
  // ...parse; throw ApiError(status, code, message, details) on failure
}
```

- One `ApiError` class carries the API's `{ error: { code, message, details } }`. Screens
  switch on `error.code`, show `error.message`, and forms map `details` to field errors
  (`fieldErrors()` in `src/api/errors.ts`).
- `error.isConflict` (409) means "the record changed since you loaded it": the UI offers to
  reload instead of retrying.
- **Idempotency keys** (`src/api/idempotency.ts`): every state-changing dialog creates one
  key per attempt, so a double click or a retry after a network error applies once. After a
  4xx the key is rotated (`keyAfterFailure`), because fixing the input is a new attempt.
- `VITE_API_URL` is read at build time (`import.meta.env`), which is why the deploy passes
  it as a build argument.

## 12. How the app boots and how login works

```ts
// src/main.ts (trimmed)
const app = createApp(App)
app.use(createPinia())
app.use(router)

setUnauthenticatedHandler(() => {           // any 401 → back to the login
  useAuthStore().reset()
  const current = router.currentRoute.value
  if (!current.meta.public) router.replace({ name: 'login', query: { redirect: current.fullPath } })
})

router.isReady().then(() => app.mount('#app'))
```

1. Create the app, install Pinia and the router (plugins, like wrapping `<App>` in
   providers).
2. The router resolves the first URL, running the guard, which asks the API once whether
   the cookie still holds a session (`GET /session`).
3. Only then is the app mounted, so a signed-out visitor never sees the back-office flash.
4. `App.vue` picks the shell: the login renders alone, every other route inside
   `AppLayout` (sidebar, header, clock).

```vue
<!-- src/App.vue -->
<RouterView v-if="route.meta.public" />
<AppLayout v-else />
```

5. Signing in (`src/features/auth/LoginView.vue`) calls the store, then
   `router.replace(safeRedirect(route.query.redirect))`. `safeRedirect` only accepts
   internal paths, so the login can't be used as an open redirect.
6. "Sign out" in the sidebar calls `auth.signOut()` and goes to the login.
7. If a session expires while you work, the next request's 401 triggers the handler from
   step 1, and you land on the login with a `redirect` back to where you were.

## 13. Styling with Tailwind v4

Tailwind v4 is configured in CSS, not in a JS config file:

```css
/* src/assets/main.css */
@import 'tailwindcss';

@theme {
  --color-surface: #ffffff;
  --color-ink: #16181d;
  --color-accent: #3d5afe;
  --color-status-active: #1b8a4b;
  --color-status-past-due: #c77700;
  /* ... */
}
```

Each `--color-*` token becomes utilities: `bg-surface`, `text-ink`, `border-accent`,
`text-status-active`, `bg-status-past-due/10` (10% opacity). Status colors are defined once
and reused by badges, the dashboard and the dunning board.

One Tailwind rule to remember: class names must appear **literally** in the source. That is
why `StatusBadge.vue` keeps a map of full class strings instead of building
`` `text-status-${status}` `` at runtime.

## 14. TypeScript with Vue

- `<script setup lang="ts">` enables TS in a component.
- Props and emits are typed with generics: `defineProps<{ status: SubscriptionStatus }>()`,
  `defineEmits<{ created: [customer: CustomerDetail] }>()`.
- `defineModel<boolean>('open', { required: true })`.
- `useTemplateRef<HTMLDialogElement>('dialog')`.
- Type-checking `.vue` files needs `vue-tsc` (`pnpm type-check`), since plain `tsc`
  doesn't understand templates. With the Vue extension in your editor (Vue - Official),
  templates are type-checked too: a wrong prop in a template is a red squiggle.
- Route meta is typed by augmenting vue-router's interface (end of `src/router/index.ts`).

## 15. Testing with Vitest, Vue Test Utils and Playwright

Vitest is Jest-compatible (`describe`, `it`, `expect`, `vi.fn()` ≈ `jest.fn()`), and
`@vue/test-utils` mounts components (≈ React Testing Library's `render`).

```ts
// src/components/__tests__/StatusBadge.spec.ts
it.each(SUBSCRIPTION_STATUSES)('renders a label and its own color for %s', (status) => {
  const wrapper = mount(StatusBadge, { props: { status } })
  expect(wrapper.text()).not.toBe('')
  expect(wrapper.classes().join(' ')).toContain(`text-status-${status.replace('_', '-')}`)
})
```

Most tests here are for plain functions, where the logic worth testing lives:

- `src/api/__tests__/*.spec.ts` stub `fetch` (`vi.stubGlobal('fetch', ...)`) and check what
  is sent (URLs, bodies, `credentials`, idempotency headers).
- `src/stores/__tests__/auth.spec.ts` tests a Pinia store with `setActivePinia(createPinia())`.
- `src/router/__tests__/redirect.spec.ts` tests `safeRedirect` against open-redirect tricks.

Run `pnpm test:unit` (watch mode) or `pnpm test:unit --run`.

### End-to-end tests (Playwright)

`web/e2e/` drives a real Chromium against the real API ([docs/17](docs/17-e2e-tests.md)).
If you have used Playwright or Cypress with React, nothing changes: the tests don't know or
care that the app is Vue, which is the point of testing through the browser.

```ts
// e2e/subscription-lifecycle.spec.ts
await page.getByRole('button', { name: 'New customer' }).click()
await page.getByLabel('Studio name').fill(name)
await page.getByRole('button', { name: 'Create customer' }).click()
await expect(page.getByRole('heading', { name })).toBeVisible()
```

- Locators (`getByRole`, `getByLabel`) find elements the way a user or a screen reader
  would, which also checks that labels and roles are right.
- `expect(...)` **retries** until it passes or times out, so there are no manual waits
  after a click that triggers a request.
- `pnpm test:e2e:ui` opens a UI to run one test, watch it, and step through each action
  with a DOM snapshot.

## 16. Tooling

```sh
pnpm dev               # Vite dev server (bin/dev at the root runs it with the API)
pnpm type-check        # vue-tsc
pnpm lint              # oxlint + eslint (with the Vue plugin)
pnpm test:unit --run   # Vitest
pnpm build-only        # production bundle in dist/
```

- **Vite** serves `.vue` files through `@vitejs/plugin-vue`, with hot reload that keeps
  component state.
- **Vue DevTools** (`vite-plugin-vue-devtools`, in dev only): inspect components, their
  refs and computed values, Pinia stores and routes, like React DevTools.
- The `@/` import alias points at `src/` (`vite.config.ts`, `tsconfig.app.json`).

## 17. Gotchas for React developers

- **Forgetting `.value`.** In `<script>`, a ref is a box: `if (pending)` is always truthy
  (it's an object). Use `pending.value`. In the template, no `.value`.
- **Destructuring kills reactivity.** `const { user } = useAuthStore()` or
  `const { name } = reactive({...})` copies the current value once. Keep the object
  (`auth.user`) or use `storeToRefs` / `toRefs`.
- **Replacing a `reactive` object.** `form = { ... }` breaks the link (and `const` stops you).
  Mutate fields or use `Object.assign(form, {...})`, as the dialogs do.
- **Mutating props.** Props are read-only; to change a parent's value, emit an event or use
  `defineModel`.
- **`v-if` vs `v-show`.** `v-if` creates and destroys (runs setup again); `v-show` only
  hides. `BaseDialog` uses `v-if="open"` inside the `<dialog>` so a reopened form starts
  fresh.
- **`v-if` with `v-for` on the same element.** Don't: `v-if` wins and can't see the loop
  variable. Filter in a `computed`, or wrap with `<template v-for>`.
- **`watch` doesn't run immediately.** Use `onMounted` or `{ immediate: true }` for the
  first run.
- **Keys still matter.** `v-for` needs a stable `:key`, same reasons as React.

## 18. Exercises

Run `pnpm lint && pnpm type-check && pnpm test:unit --run` after each.

1. **Reactivity by hand.** In `DashboardView.vue`, add a `computed` with the share of paying
   subscriptions (`paying_subscriptions / total`) and show it in the MRR tile. No
   dependency array; watch it update when you advance the clock.
2. **A prop.** Give `PaginationNav.vue` a `compact` prop that hides the
   "· 12 runs" total after "Page 1 of 1", and use it in the Scenario Lab's recent runs.
3. **`v-model` on a component.** Build a `StatusSelect.vue` with
   `defineModel<string>()` rendering the status `<select>`, and use it in
   `SubscriptionsView.vue` with `v-model` instead of the current `:value`/`@change` pair.
4. **A composable.** Extract the 300 ms search debounce from `SubscriptionsView.vue` into
   `useDebouncedRef(source, ms)` in `src/composables/`, with a Vitest test using fake timers
   (`vi.useFakeTimers()`), and reuse it in the customers list.
5. **A store.** Add a `preferences` Pinia store that remembers the last status filter per
   list in `localStorage` (wrapped in try/catch), and restore it when a list opens without
   a filter.
6. **A route.** Add `/plans/:id` showing one plan (the API already has `GET /plans/:id`):
   route with lazy import, view with `useAsyncData`, links from the plans table.

## 19. Where to go next

- [Vue guide](https://vuejs.org/guide/introduction.html): read *Essentials* and
  *Components In-Depth* with the Composition API toggle on; *Reactivity in Depth* explains
  the Proxy magic.
- [Vue for React developers](https://vuejs.org/guide/extras/composition-api-faq.html)
  (Composition API FAQ, including "Comparison with React Hooks").
- [Pinia](https://pinia.vuejs.org/) and [Vue Router](https://router.vuejs.org/) docs.
- [Vue Test Utils](https://test-utils.vuejs.org/) and [Vitest](https://vitest.dev/).
- The Vue DevTools panel while clicking around this app: the fastest way to see refs,
  computed values and stores change live.
