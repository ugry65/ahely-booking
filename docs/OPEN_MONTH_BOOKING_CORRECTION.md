# Múltbeli admin foglaláskorrekció nyitott hónapban

2026-10-14. Imre: az admin a nyitott hónap múltbeli foglalását tudja szerkeszteni,
például 08–17 helyett09–17 használatra. Külön fejlesztés, a befizetésrögzítéssel
együtt ellenőrizhető stagingen; production GO nincs.

Napi naptár → múltbeli foglalás → Szerkesztés → kötelező korrekciós indok.
Csak a kiválasztott egyetlen alkalom módosulhat, sorozatban is. Ez új, explicit
kivétel a korábbi múltbeli sorozatszerkesztés tiltására; a jövőbeli sorozatművelet
három hatóköre változatlan. Régi UI baselineokat történeti bizonyítékként megőrizzük.
Az automatikus havi díj/óraszám újraszámolódik. A tényleges befizetés, foglaló,
egyedi booking óradíj és sorozatkapcsolat megmarad. Egyedi óradíj korrekcióját
továbbra is külön pénzügyi művelet kezeli, nem ez a szerkesztő.

DB: admin_correct_open_month_booking, aktív-admin guard, required reason,
eredeti updated_at optimistic check, payload/key idempotencia, room locks,
NO KEY UPDATE, sorted source/target period locks és closure recheck. Zárt
publikált hónap és legacy partial is_closed bármelyik érintett hónapban tiltott.
Az eredeti assert_booking_request és exclusion constraint védi a helyiségjogot,
nyitvatartást, időrácsot, minimum időt és ütközést. booking.updated before/after
audit kötelező indokkal, meglévő update/outbox/booking-email bridge contract.
Régi normál-user cutoff és pricing setter nem lazul. Korábbi receipt havi
hozzárendelése miatt befizetett booking hónapja nem cserélhető észrevétlenül.

Státusz: implementáció/pgTAP/CI/független review folyamatban. Staging még nincs
frissítve ezzel a változtatással. Éles rendszer változatlan.
