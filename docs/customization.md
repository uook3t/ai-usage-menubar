# Personal customization

Based on upstream AI Usage v0.2.1 (`3df27e9081192bc5c954f932e4e807e097a49c02`).
Fork: https://github.com/uook3t/ai-usage-menubar
Branch: `customization/vpn-usage`. Official repository is remote `upstream`; personal fork is `origin`.

## Behavior

- Claude Code, Codex and VPN are tracked by default. Other upstream providers remain available in Settings.
- Default menu bar layout stacks a small provider name above its number. Settings can restore the upstream single-line layout. VPN's editable label is limited to 12 characters, defaults to VPN, and is shared with its dashboard card.
- VPN always reports **used** percentage, one decimal place, independently of the AI providers' Left/Used control. Orange at 80%, red at 95%; percentages above 100% remain visible while progress drawing is bounded.
- VPN settings include a masked HTTPS query URL (with optional reveal), a name preview, and an independent 1–60 minute refresh interval, default 5 minutes. Save applies configuration and refreshes VPN.
- The JustMySocks adapter reads `monthly_bw_limit_b`, `bw_counter_b`, and optional `bw_reset_day_of_month`. Decimal GB uses 1,000,000,000 bytes. The card shows used, limit, remaining, overage, monthly reset day and last successful update. No exact reset time is inferred.
- Transient failures preserve the last successful VPN data and show an error. The stacked menu item adds `!`; missing data is `--`.
- Sleep stops requests/timers; wake resumes them and immediately refreshes stale data.
- Launch at Login starts off. Registration and unregistration were verified on the installed local build.
- Upstream automatic updates and the update action are disabled so an official binary cannot replace the customized app.

## Storage

As requested, VPN URL, label and interval use `AppPreferences` / `UserDefaults`, alongside ordinary upstream preferences. The URL includes access credentials and is readable in the local preferences file. It is masked in the UI, omitted from logs and never embedded in source or build artifacts. No new Keychain item is used.

VPN's last good numeric snapshot is cached in UserDefaults with an endpoint SHA-256 fingerprint. A different endpoint cannot restore that snapshot; cancellation prevents a late response from overwriting the new configuration. AI data retains upstream's in-memory behavior.

Requests use an ephemeral URLSession with no persistent cookies or cache, a 20-second request timeout and a 25-second resource timeout. Redirects are rejected to keep the query credential on its configured endpoint. Use the final HTTPS endpoint directly.

## Build / install

```sh
./scripts/install.sh
```

The custom bundle identifier is `local.yanjun.aiusage`; the installer uses local ad-hoc signing and installs `~/Applications/AI Usage.app`. This is a local build, not a notarized distribution. The original VPNUsage app is kept separately as a rollback option.

For one-time local provisioning, the executable accepts `--configure-vpn-stdin`. The URL is read from standard input rather than process arguments. Prefer the Settings UI for normal use.

## Extension points

`UsageProvider` remains the upstream provider boundary. New bounded resources can reuse `ResourceUsage` (base-unit values, display unit/divisor, optional reset day), the resource details view and `ProviderSnapshot.resourceUsage`. A new service still needs a provider adapter, catalog registration and settings integration; this is not a user-configurable JSON mapping system.

The customized surface is concentrated in the VPN provider files, stacked menu renderer, VPN settings, and the store's independent VPN scheduling. To update, fetch `upstream`, select a stable release, merge it into the customization branch and resolve changes at these integration points. Preserve upstream MIT LICENSE and NOTICE.

## Validation

The complete 100-test suite passed after the implementation and storage changes. Two additional focused tests cover late responses after endpoint changes and VPN preference persistence. Release build and signature verification passed. Actual Codex and VPN requests succeeded; Claude currently reports that its CLI login is missing.

UI checks covered masked URL, Chinese labels, interval changes, default restoration and login startup on/off. A temporary one-minute interval produced a later persisted fetch timestamp; restored to five minutes. Physical sleep/wake and logout/login were not exercised to avoid interrupting the session.
