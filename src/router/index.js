import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const HomeView = () => import('../views/HomeView.vue')
const PublicTournamentView = () => import('../views/PublicTournamentView.vue')
const ClubPageView = () => import('../views/ClubPageView.vue')
const ClubRegistrationView = () => import('../views/ClubRegistrationView.vue')
const ClubRegistrationStatusView = () => import('../views/ClubRegistrationStatusView.vue')
const AdminLayout = () => import('../views/AdminLayout.vue')
const AdminTournamentListView = () => import('../views/AdminTournamentListView.vue')
const AdminTournamentCreateView = () => import('../views/AdminTournamentCreateView.vue')
const AdminTournamentView = () => import('../views/AdminTournamentView.vue')
const AdminSettingsView = () => import('../views/AdminSettingsView.vue')
const ClubSettingsView = () => import('../views/ClubSettingsView.vue')
const InviteAcceptView = () => import('../views/InviteAcceptView.vue')
const SuperAdminLayout = () => import('../views/SuperAdminLayout.vue')
const SuperAdminDashboardView = () => import('../views/SuperAdminDashboardView.vue')

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/',
      name: 'home',
      component: HomeView,
      async beforeEnter() {
        const auth = useAuthStore()
        if (!auth.ready) {
          await auth.init()
        }
        if (auth.user) {
          await auth.checkClubStatus()
          if (auth.clubStatus === 'active') {
            return { name: 'admin-tournaments' }
          }
        }
        return true
      },
    },
    {
      path: '/tournaments/:slug',
      name: 'public-tournament',
      component: PublicTournamentView,
      props: true,
    },
    {
      path: '/clubs/:slug',
      name: 'public-club',
      component: ClubPageView,
      props: true,
    },
    {
      path: '/invites/:token',
      name: 'invite-accept',
      component: InviteAcceptView,
      props: true,
    },
    {
      path: '/register-club',
      name: 'club-register',
      component: ClubRegistrationView,
      async beforeEnter() {
        const auth = useAuthStore()
        if (!auth.ready) await auth.init()
        if (auth.user) {
          await auth.checkClubStatus()
          if (auth.clubStatus) {
            return { name: 'club-registration-status' }
          }
        }
        return true
      },
    },
    {
      path: '/register-club/status',
      name: 'club-registration-status',
      component: ClubRegistrationStatusView,
      meta: { requiresAuth: true },
      async beforeEnter() {
        const auth = useAuthStore()
        if (!auth.ready) await auth.init()
        if (auth.user) {
          await auth.checkClubStatus()
          if (auth.clubStatus === 'active') {
            return { name: 'admin-tournaments' }
          }
        }
        return true
      },
    },
    {
      path: '/admin',
      component: AdminLayout,
      meta: { requiresAuth: true, requiresActiveClub: true },
      redirect: { name: 'admin-tournaments' },
      children: [
        {
          path: 'tournaments',
          name: 'admin-tournaments',
          component: AdminTournamentListView,
        },
        {
          path: 'tournaments/new',
          name: 'admin-tournament-new',
          component: AdminTournamentCreateView,
        },
        {
          path: 'tournaments/:id',
          name: 'admin-tournament',
          component: AdminTournamentView,
          props: true,
        },
        {
          path: 'settings',
          name: 'admin-settings',
          component: AdminSettingsView,
        },
        {
          path: 'club',
          name: 'admin-club-settings',
          component: ClubSettingsView,
          async beforeEnter() {
            const auth = useAuthStore()
            if (!auth.ready) await auth.init()
            await auth.loadTournamentRoles()
            const isCounterOnly =
              auth.tournamentRoles.length > 0
              && auth.tournamentRoles.every((r) => r === 'counter')
              && auth.clubStatus !== 'active'
            if (isCounterOnly) return { name: 'admin-tournaments' }
            return true
          },
        },
      ],
    },
    {
      path: '/superadmin',
      component: SuperAdminLayout,
      redirect: { name: 'superadmin-clubs' },
      children: [
        {
          path: 'clubs',
          name: 'superadmin-clubs',
          component: SuperAdminDashboardView,
        },
      ],
    },
  ],
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()

  if (!auth.ready) {
    await auth.init()
  }

  const requiresAuth = to.matched.some((record) => record.meta.requiresAuth)
  if (requiresAuth && !auth.user) {
    return { name: 'home' }
  }

  const requiresActiveClub = to.matched.some((record) => record.meta.requiresActiveClub)
  if (requiresActiveClub && auth.user) {
    if (to.name === 'admin-tournaments' || to.name === 'admin-tournament') {
      return true
    }
    if (auth.clubStatus === null) {
      await auth.checkClubStatus()
    }
    if (auth.clubStatus && auth.clubStatus !== 'active') {
      return { name: 'club-registration-status' }
    }
  }

  const requiresSuperAdmin = to.matched.some((record) => record.meta.requiresSuperAdmin)
  if (requiresSuperAdmin) {
    await auth.checkPlatformRole()
    if (auth.platformRole !== 'superadmin') {
      return { name: 'home' }
    }
  }

  return true
})

export default router
