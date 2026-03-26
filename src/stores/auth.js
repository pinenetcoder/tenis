import { defineStore } from 'pinia'
import { supabase } from '../lib/supabase'

let authSubscription = null

export const useAuthStore = defineStore('auth', {
  state: () => ({
    user: null,
    session: null,
    ready: false,
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
