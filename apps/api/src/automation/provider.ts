export type ProviderSnapshot = {
  accounts: Array<{
    providerId: string; name: string; institution: string;
    kind: "checking" | "savings" | "credit" | "investment" | "cash";
    balanceMinor: number; currency: string;
  }>;
  transactions: Array<{
    providerId: string; providerAccountId: string; description: string;
    amountMinor: number; currency: string; bookedAt: Date; pending: boolean;
  }>;
};

export interface BankProvider {
  readonly name: string;
  checkConnection(providerItemId: string): Promise<{ ok: boolean; reason?: string }>;
  fetchSnapshot(providerItemId: string): Promise<ProviderSnapshot>;
}

/** Safe deterministic provider for local development and end-to-end sync testing. */
export class DemoBankProvider implements BankProvider {
  readonly name = "demo";

  async checkConnection() { return { ok: true }; }

  async fetchSnapshot(): Promise<ProviderSnapshot> {
    const day = new Date().toISOString().slice(0, 10);
    return {
      accounts: [{ providerId: "demo-checking", name: "Everyday", institution: "Demo Bank", kind: "checking", balanceMinor: 245_832, currency: "USD" }],
      transactions: [
        { providerId: `coffee-${day}`, providerAccountId: "demo-checking", description: "Corner Coffee", amountMinor: -525, currency: "USD", bookedAt: new Date(`${day}T08:00:00Z`), pending: false },
        { providerId: `salary-${day}`, providerAccountId: "demo-checking", description: "Salary", amountMinor: 320_000, currency: "USD", bookedAt: new Date(`${day}T06:00:00Z`), pending: false },
      ],
    };
  }
}
