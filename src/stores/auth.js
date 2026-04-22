import { defineStore } from 'pinia'
import { supabase } from '../lib/supabase'

let authSubscription = null

export const useAuthStore = defineStore('auth', {
  state: () => ({
    user: null,
    session: null,
    ready: false,
    platformRole: null,
    clubStatus: null, // null | 'pending' | 'active' | 'rejected'
  }),
  actions: {
    async init() {
      if (this.ready) {
        return
      }

      const { data, error } = await supabase.auth.getSession()
      if (error) {
        throw error
      }

      this.session = data.session
      this.user = data.session?.user ?? null
      this.ready = true

      if (!authSubscription) {
        const { data: subscriptionData } = supabase.auth.onAuthStateChange((_event, session) => {
          this.session = session
          this.user = session?.user ?? null
          this.ready = true
        })
        authSubscription = subscriptionData.subscription
      }
    },

    async signInWithGoogle() {
      const redirectTo = `${window.location.origin}/admin`
      const { error } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: { redirectTo },
      })

      if (error) {
        throw error
      }
    },

    async signInWithGoogleForRegistration() {
      const redirectTo = `${window.location.origin}/register-club?step=complete`
      const { error } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: { redirectTo },
      })
      if (error) throw error
    },

    async signUpWithEmail(email, password) {
      const { data, error } = await supabase.auth.signUp({ email, password })
      if (error) throw error
      this.session = data.session
      this.user = data.session?.user ?? null
      return data
    },

    async checkClubStatus() {
      if (!this.user) {
        this.clubStatus = null
        return
      }
      const { data } = await supabase
        .from('clubs')
        .select('status')
        .eq('owner_id', this.user.id)
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle()
      this.clubStatus = data?.status ?? null
    },

    async checkPlatformRole() {
      if (!this.user) {
        this.platformRole = null
        return
      }
      const { data } = await supabase
        .from('platform_admins')
        .select('id')
        .eq('user_id', this.user.id)
        .maybeSingle()
      this.platformRole = data ? 'superadmin' : null
    },

    async signOut() {
      const { error } = await supabase.auth.signOut()
      if (error) {
        throw error
      }
      this.user = null
      this.session = null
    },
  },
})
