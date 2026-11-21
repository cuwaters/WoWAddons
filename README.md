# WoWAddons

Personal World of Warcraft addons. Each addon lives in its own folder; link or copy a folder into `Interface\AddOns\` to use it.

## NewCharDefaults

Applies a standard UI setup the first time each character logs in:

- Action bars 2-5, Damage Meter and Cooldown Manager turned on (set as CVars; a popup offers a UI reload so they show up)
- Minimap tracking: Auctioneer, Banker, Innkeeper, Mailbox, Class Trainer, Profession Trainers, Repair, Flight Master
- Edit Mode layout "Mine" (also applied to new specs that start on a preset layout)
- General chat tab filters, plus a "Spam" tab (Say/Yell/Whisper/Party/Guild/Channel/BN Whisper)
- General, LocalDefense, Trade, Services, TradeLocal and OOC channels move to the Spam tab. Trade, Services, TradeLocal and OOC only exist in cities, so each is moved the first time the character joins it.
- Both tabs at 203/255 background opacity

Commands: `/ncd` re-applies now; `/ncd reset` re-applies on next login.

Install (Windows, from an elevated or developer-mode prompt):

    mklink /J "<WoW>\_forever_\Interface\AddOns\NewCharDefaults" "D:\dev\WoWAddons\NewCharDefaults"
