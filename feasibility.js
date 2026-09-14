window.RACE_FEASIBILITY={
  updated:"2026-09-14",
  context:"Valutazione personalizzata per Bogdan, basata sullo storico allenamenti disponibile. Tiene conto soprattutto di distanza massima coperta, continuità nelle tre discipline e carico specifico; non sostituisce una valutazione medica o un test di gara.",
  rules:[
    {
      id:"super-sprint",
      test:/\b(super\s*sprint|supersprint)\b/i,
      badge:"🟢",
      level:"Fattibilità molto alta",
      score:96,
      detail:"Distanze nettamente dentro le tue capacità attuali. Utile soprattutto come gara-test e per allenare transizioni e gestione del ritmo."
    },
    {
      id:"sprint",
      test:/\bsprint\b/i,
      badge:"🟢",
      level:"Fattibilità alta",
      score:92,
      detail:"Le distanze singole sono già coperte con margine: nuoto 750 m sotto i tuoi 2 km, bici 20 km molto sotto i tuoi lunghi e corsa 5 km già consolidata. Il punto da monitorare resta la continuità della corsa e il ginocchio."
    },
    {
      id:"olimpico",
      test:/\b(olimpico|olympic|standard)\b/i,
      badge:"🟡",
      level:"Fattibile con preparazione mirata",
      score:78,
      detail:"Hai già coperto separatamente le distanze e la bici non è un limite. Per arrivarci bene servono più continuità nel nuoto, corsa regolare e brick specifici, con attenzione al ginocchio."
    },
    {
      id:"70.3",
      test:/\b(70[.,]?3|half\s*ironman|mezzo\s*ironman|medio)\b/i,
      badge:"🟠",
      level:"Ambiziosa, non ancora pronta oggi",
      score:53,
      detail:"Il nuoto da 1,9 km è già alla tua portata e in bici sei arrivato vicino ai 90 km. Il vero gap è sostenere poi 21,1 km di corsa: servono mesi di volume progressivo, brick lunghi e stabilità del ginocchio."
    },
    {
      id:"full",
      test:/\b(ironman|full\s*distance|226|3[.,]?8\s*km.*180\s*km|140[.,]?6)\b/i,
      badge:"🔴",
      level:"Non consigliata al momento",
      score:24,
      detail:"È coerente come obiettivo futuro, ma oggi manca ancora endurance specifica soprattutto per maratona dopo 180 km di bici, oltre a volume nuoto e brick di lunga durata."
    },
    {
      id:"duathlon-sprint",
      test:/\bduathlon\b.*\bsprint\b|\bsprint\b.*\bduathlon\b/i,
      badge:"🟢",
      level:"Fattibilità alta",
      score:88,
      detail:"La bici è ampiamente coperta e le distanze di corsa sono compatibili con ciò che hai già fatto. Da gestire bene il carico sulla gamba destra e la seconda frazione di corsa."
    },
    {
      id:"duathlon",
      test:/\bduathlon\b/i,
      badge:"🟡",
      level:"Da valutare in base alle distanze",
      score:72,
      detail:"Disciplina compatibile con la tua base ciclistica; la fattibilità dipende soprattutto dalla lunghezza complessiva delle due frazioni di corsa e dallo stato del ginocchio."
    }
  ],
  overrides:[]
};
