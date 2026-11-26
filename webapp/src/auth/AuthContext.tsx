import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { getSession, onSessionChange, setSession, userIdFromToken, type Session } from './session';
import type { SessionResponse } from '../api/types';

interface Auth {
  session: Session | null;
  userId: string | undefined;
  signIn: (response: SessionResponse) => void;
  signOut: () => void;
}

const AuthContext = createContext<Auth | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setState] = useState<Session | null>(getSession());
  const queryClient = useQueryClient();
  useEffect(() => onSessionChange((next) => {
    setState(next);
    // Nothing one person loaded may show for the next
    if (!next) queryClient.clear();
  }), [queryClient]);

  const value = useMemo<Auth>(() => ({
    session,
    userId: session ? session.userId || userIdFromToken(session.token) : undefined,
    signIn: (response) => {
      queryClient.clear();
      setSession({ token: response.token, name: response.user.displayName || '', userId: response.user._id });
    },
    signOut: () => setSession(null)
  }), [session, queryClient]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): Auth {
  const value = useContext(AuthContext);
  if (!value) throw new Error('useAuth outside AuthProvider');
  return value;
}
