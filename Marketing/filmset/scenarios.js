/* Format E scenario data — see ../FORMAT-TESTS.md §4 (T2).
 *
 * Ten scenarios, one per post, for the English E-1 sample. `genz` and `corporate` are
 * the two halves of the joke; everything else exists only to make the frame believable.
 *
 * Rule for `genz`, from FORMAT-TESTS.md: write what a 21-year-old would text their
 * closest friend in this situation — not what a marketer thinks Gen Z would say.
 * If it reads as deliberately written to be funny, rewrite it.
 *
 * THE LINE HAS TO BE TRANSLATABLE. The product changes *register*, not content — it
 * makes a message polite, it does not infer a message that was never there. So every
 * line is built as **slang reaction + the actual thing being said**, and it passes one
 * test before it is filmed:
 *
 *     delete every slang word and every emoji. What is left must still be a
 *     complete message.
 *
 * `unc it's 10pm 💀 be so fr rn` fails that test — strip it and nothing is left, so a
 * rewrite promising to do the work in the morning is text the app cannot produce.
 * `unc it's 10pm 💀 i'll do it first thing tmr` passes: the slang is droppable noise,
 * the clause after it is the whole message.
 *
 * SHORT. Twelve words is the ceiling. A line that needs a pause to read has already lost
 * the post — the viewer has to clock it, laugh, and still be there when the button gets
 * pressed. `alts` holds the other lines for that situation, same rule, same length; swap
 * one in rather than growing the primary.
 *
 * `corporate` is a FALLBACK only. On camera the real KeigoButton produces this text;
 * the field exists for takes where API latency ruins the cut, and what it shows must
 * be text the product actually returned, pasted back in here.
 *
 * The same translatability rule binds it: every fact in the rewrite has to come from the
 * Gen Z line, never from the boss's message. An earlier draft here promised the deck
 * "ahead of the 9am" and referred to a summary sent "last Thursday" — both were details
 * only the boss said, so no rewrite of the user's own text could produce them.
 */
window.ME = { name: 'Maya Reyes', initial: 'M', color: '#3D7C6B' };

/* One POV across all ten, per FORMAT-TESTS.md §5 — the Gen Z line is the variable
 * being tested, so the hook is held still. The rest of the §4 bank is the next sample,
 * not this one. */
const POV = "pov: you're a 22 year old working in corporate";

/* Three bosses. Rotated so no name, avatar or scrollback carries more than four posts —
 * at the default --fill the sidebar is outside the 9:16 crop, so the boss's name, their
 * avatar and their last message are the only things a repeat viewer actually recognises. */
const CASTS = {
  diane: {
    workspace: 'Meridian Group', name: 'Diane Whitaker', initial: 'D', color: '#B4562F',
    title: 'Director of Marketing',
    scrollback: [
      { boss: true, time: 'Yesterday at 11:02 AM', text: 'Can you pull the campaign numbers into the shared sheet before the sync?' },
      { me: true,   time: 'Yesterday at 11:04 AM', text: 'yep on it' },
      { me: true,   time: 'Yesterday at 12:47 PM', text: 'added them, plus a tab for last quarter so we can compare' },
      { boss: true, time: 'Yesterday at 1:15 PM',  text: 'Perfect, thank you.' },
      { boss: true, time: 'Yesterday at 4:12 PM',  text: 'Thanks for turning the notes around so fast today.' },
      { me: true,   time: 'Yesterday at 4:15 PM',  text: 'ofc! lmk if anything else comes up' },
      { me: true,   time: '9:41 AM',               text: 'morning! just grabbed the Q3 deck 👍' }
    ]
  },
  greg: {
    workspace: 'Meridian Group', name: 'Greg Halvorsen', initial: 'G', color: '#4A6FA5',
    title: 'VP, Operations',
    scrollback: [
      { me: true,   time: 'Monday at 9:12 AM',   text: 'morning! the vendor list is in the ops folder now' },
      { boss: true, time: 'Monday at 9:40 AM',   text: 'Great. Add the renewal dates when you get a minute.' },
      { me: true,   time: 'Monday at 2:31 PM',   text: 'done ✅ two of them renew in October fyi' },
      { boss: true, time: 'Monday at 2:35 PM',   text: 'Good catch.' },
      { boss: true, time: 'Yesterday at 5:02 PM', text: 'Can you sit in on the Thursday review? Just to take notes.' },
      { me: true,   time: 'Yesterday at 5:04 PM', text: 'sure!! put it in my calendar' },
      { me: true,   time: '4:58 PM',              text: 'notes from today are in the doc 🙌' }
    ]
  },
  tobias: {
    workspace: 'Meridian Group', name: 'Tobias Renner', initial: 'T', color: '#7A5C2E',
    title: 'Head of Growth',
    scrollback: [
      { boss: true, time: 'Monday at 8:52 AM',   text: 'Morning — could you own the weekly numbers post from now on?' },
      { me: true,   time: 'Monday at 8:55 AM',   text: 'yes!! happy to 🙌' },
      { me: true,   time: 'Monday at 4:20 PM',   text: 'posted it! added a line on why signups dipped' },
      { boss: true, time: 'Monday at 4:44 PM',   text: 'Nice. That extra line is exactly the sort of thing to keep doing.' },
      { boss: true, time: 'Yesterday at 11:31 AM', text: 'Are you across the roadmap doc yet?' },
      { me: true,   time: 'Yesterday at 11:33 AM', text: 'reading it now! it’s a lot 😅' },
      { me: true,   time: '10:02 AM',              text: 'morning! working through the growth tab today 👀' }
    ]
  },
  cecilia: {
    workspace: 'Meridian Group', name: 'Cecilia Vance', initial: 'C', color: '#A03D5C',
    title: 'Client Partner',
    scrollback: [
      { me: true,   time: 'Tuesday at 9:47 AM',  text: 'morning! the Harlow notes are typed up 📝' },
      { boss: true, time: 'Tuesday at 10:05 AM', text: 'Thank you. Could you also chase them on the missing brief?' },
      { me: true,   time: 'Tuesday at 3:12 PM',  text: 'chased! they said end of week' },
      { boss: true, time: 'Tuesday at 3:14 PM',  text: 'Great, thanks for staying on it.' },
      { boss: true, time: 'Yesterday at 2:40 PM', text: 'Client loved the deck by the way. Well done.' },
      { me: true,   time: 'Yesterday at 2:41 PM', text: 'omg thank you 🥹' },
      { me: true,   time: '9:15 AM',              text: 'morning!! coffee then Harlow follow up ☕️' }
    ]
  },
  nadia: {
    workspace: 'Meridian Group', name: 'Nadia Okonjo', initial: 'N', color: '#2F6E4E',
    title: 'Programme Lead',
    scrollback: [
      { boss: true, time: 'Monday at 1:04 PM',   text: 'Adding you to the steering group — you’ll get a lot of calendar invites, sorry in advance.' },
      { me: true,   time: 'Monday at 1:06 PM',   text: 'haha no worries! excited' },
      { boss: true, time: 'Wednesday at 10:22 AM', text: 'Could you take the actions log for Thursday?' },
      { me: true,   time: 'Wednesday at 5:48 PM', text: 'actions log is up to date ✅ 6 open items' },
      { boss: true, time: 'Yesterday at 8:59 AM', text: 'Perfect. You’re making this much easier.' },
      { me: true,   time: 'Yesterday at 9:01 AM', text: 'ahh thank you 😄' },
      { me: true,   time: '11:58 AM',             text: 'just closed two more items off the log 👍' }
    ]
  },
  priya: {
    workspace: 'Meridian Group', name: 'Priya Raman', initial: 'P', color: '#6B4E9E',
    title: 'Head of Client Strategy',
    scrollback: [
      { boss: true, time: 'Tuesday at 10:15 AM', text: 'Welcome to the account! I’ll add you to the client channel.' },
      { me: true,   time: 'Tuesday at 10:16 AM', text: 'thank youuu excited 🙏' },
      { boss: true, time: 'Wednesday at 3:22 PM', text: 'Could you take a first pass at the onboarding deck?' },
      { me: true,   time: 'Wednesday at 6:10 PM', text: 'first pass is in the folder! flagged two slides i wasnt sure about' },
      { boss: true, time: 'Yesterday at 9:30 AM', text: 'This is a really strong start, thank you.' },
      { me: true,   time: 'Yesterday at 9:32 AM', text: 'ahh ok good 😅 happy to keep going on it' },
      { me: true,   time: '11:20 AM',             text: 'sent the revised slides over 👀' }
    ]
  }
};

/* One row per post. `pre` is an optional extra message before the trigger, for
 * situations the shared scrollback would otherwise contradict. */
const SCENES = [
  {
    id: 'e-001', cast: 'diane', situation: 'confused by a jargon-soup request',
    time: '10:24 AM',
    trigger: 'Morning. Before we lock scope — can you socialize the revised framing with the stakeholders and make sure we’re directionally aligned on the Q3 narrative? Would be great to have a POV by EOD.',
    genz: 'bro is yapping 😭 i don’t get it can u explain',
    alts: ['twin i’m lost 💀 what do u want me to do exactly', 'no bc none of that was english 😭 can u break it down', 'i fear i don’t get it 💀 can we hop on a call'],
    corporate: 'Thank you for the additional detail. I’m afraid I don’t fully follow — would you mind explaining what you’d like me to cover?'
  },
  {
    id: 'e-002', cast: 'greg', situation: 'pinged at 9:47 PM',
    time: '9:47 PM',
    trigger: 'Sorry for the late ping — any chance you could take a look at the deck tonight? Would be good to have it clean before the 9am.',
    genz: 'unc it’s 10pm 💀 i’ll do it first thing tmr',
    alts: ['bro my laptop is closed 😭 i’ll sort it in the morning', 'twin it’s almost 10pm 💀 first thing tomorrow ok', 'nahhh not tonight 😭 i’ll have it before the 9am'],
    corporate: 'Thanks for flagging this. It is rather late on my end, so I will make it my first priority in the morning.'
  },
  {
    id: 'e-003', cast: 'priya', situation: 'messaged while on PTO',
    time: '10:08 AM',
    pre: [{ me: true, time: 'Yesterday at 5:58 PM', text: 'heads up i’m off thurs + fri! everything’s handed over 🙌' }],
    trigger: 'Quick one — do you know where the updated client tracker lives? I can’t find it anywhere.',
    genz: 'twin i’m on pto rn 😭 i’ll send it monday',
    alts: ['bro i’m on pto 💀 i’ll get it to u monday', 'girl i’m literally at the airport 😭 monday ok?', 'chat i’m on annual leave 💀 i’ll send it when i’m back'],
    corporate: 'Apologies for the delay — I am currently on annual leave. I will send it across on Monday.'
  },
  {
    id: 'e-004', cast: 'diane', situation: 'asked to jump on a call',
    time: '2:12 PM',
    trigger: 'Rather than going back and forth here, do you have 15 minutes this afternoon?',
    genz: 'no shot 😭 can u just type it out instead',
    alts: ['bro a whole call?? 💀 just send it in a message', 'twin i’m not using my voice today 😭 can u write it', 'nooo pls 😭 can we just do this over text'],
    corporate: 'Thank you for the offer. Rather than a call, would you mind putting it in writing instead? I would greatly appreciate it.'
  },
  {
    id: 'e-005', cast: 'greg', situation: 'new work at 5:41 PM on a Friday',
    time: '5:41 PM',
    trigger: 'One more thing before you log off — would be great to get this over the line before Monday.',
    genz: 'on a friday?? 💀 i’m logging off i’ll do it monday',
    alts: ['bro it’s 5:41 on a friday 😭 monday ok?', 'twin crazy work 💀 i’ll pick it up monday morning', 'nah i’m gone 😭 first thing monday i promise'],
    corporate: 'As it is Friday, I am going to log off for the evening — I will pick this up on Monday.'
  },
  {
    id: 'e-006', cast: 'priya', situation: 'asked for work already delivered',
    time: '11:46 AM',
    trigger: 'Could you put together a short summary of the campaign numbers when you get a chance?',
    genz: 'twin i already sent this last week 😭 check ur dms',
    alts: ['bro scroll up 💀 i sent this thursday', 'we did this last week 😭 it’s in the folder', 'girl i already made this 💀 want it in a different format?'],
    corporate: 'Happy to help — I believe I already sent this last week, so it may be worth checking back through our messages.'
  },
  {
    id: 'e-007', cast: 'greg', situation: 'blamed for someone else’s miss',
    time: '9:05 AM',
    trigger: 'Looks like the deck went out without the updated figures. I think that was on your side?',
    genz: 'nahhh that wasn’t me 💀 i sent the final one tuesday',
    alts: ['bro pull up the thread 😭 i handed it over tuesday', 'LMAOOOO not me 💀 the final version went over tuesday', 'twin i flagged this in march 😭 check the thread'],
    corporate: 'Thanks for raising this — I do not believe that was on my side. The final version was sent over on Tuesday.'
  },
  {
    id: 'e-008', cast: 'diane', situation: 'a 60-minute meeting with no agenda',
    time: '4:33 PM',
    trigger: 'Popped 60 minutes on your calendar tomorrow to run through a few things.',
    genz: 'an hour?? 😭 can u send an agenda or make it 30',
    alts: ['bro 60 whole minutes 💀 what’s on the agenda', 'twin can we make it 30 😭 i’ll come prepared', 'nah what is this about 💀 can u send an agenda'],
    corporate: 'Thank you for setting that up. Would you mind sharing an agenda beforehand, or alternatively condensing it to thirty minutes?'
  },
  {
    id: 'e-009', cast: 'priya', situation: 'a vague ownership grab',
    time: '3:07 PM',
    trigger: 'Going forward I’d like you to own this end to end and really drive it forward.',
    genz: 'own what 😭 like what am i actually doing here',
    alts: ['own what exactly 💀 where does my bit start and stop', 'twin that’s three jobs 😭 what’s actually mine', 'bro what does that mean day to day 💀'],
    corporate: 'Thank you — could I ask what that would involve in practice? I would like to be clear on exactly what falls to me.'
  },
  {
    id: 'e-010', cast: 'greg', situation: 'blunt feedback on your work',
    time: '1:19 PM',
    trigger: 'Had a look at the draft. Honestly, I think it needs a fairly significant rethink.',
    genz: 'damn ok 💀 which bits do u want me to redo',
    alts: ['ok crazy work 😭 tell me which parts to change', 'twin say it with ur chest 💀 what needs redoing', 'aura -1000 😭 which sections should i start with'],
    corporate: 'I appreciate the candid feedback. Would you mind letting me know which sections you would like me to rework?'
  },

  /* ── batch two, 2026-08-23. Register per LINEBANK.md §1: the speaker is powerless and
   * cheerful about it. Structure is deliberately uneven — two lines carry no emoji at all,
   * one opens on one, four end on one, and the emoji itself changes every time. Ten
   * identical `slang 😭 clause` lines read as a template rather than as texting. */
  {
    id: 'e-011', batch: 2, cast: 'tobias', situation: 'a jargon-soup request',
    time: '10:41 AM',
    trigger: 'Before we go further — let’s make sure we’re double-clicking on the right levers here rather than boiling the ocean on the whole roadmap. Can you take a first cut at that framing?',
    genz: 'bro what. i genuinely don’t know what any of that means',
    alts: ['ok i understood zero of that. can u say it normally',
           'twin what are levers 💀 pls explain in english',
           'i’ve read that 3 times and i still don’t get it'],
    corporate: 'Apologies — I’m afraid I don’t follow this. Would you mind explaining what you’d like me to look at?'
  },
  {
    id: 'e-012', batch: 2, cast: 'cecilia', situation: 'asked about work you forgot entirely',
    time: '2:58 PM',
    trigger: 'How’s the Harlow deck coming along? Hoping to look at it before I speak to them.',
    genz: 'lmaooo i completely forgot can i get it to u friday 🙏',
    alts: ['omg this completely slipped my mind. friday ok?',
           'i forgot 💀 giving it to u friday i promise',
           'ngl i haven’t started. can i have til friday'],
    corporate: 'Apologies, this had completely slipped my mind. Would Friday work for getting it over to you?'
  },
  {
    id: 'e-013', batch: 2, cast: 'nadia', situation: 'a long motivational corporate paragraph',
    time: '9:12 AM',
    trigger: 'Morning! Before you dive in — as we head into the second half I really want us to be intentional about how we show up for each other, bringing our full selves, championing the work, and holding a high bar on everything that leaves this team. Genuinely excited for what you build here.',
    genz: 'lmaooo fam stop with the aura farming 💀 what do u need',
    alts: ['ok but what do u actually want me to do',
           'twin this is so much yapping. what’s the ask',
           'i love this for u 😀 but what do u need from me'],
    corporate: 'I appreciate the context, though I’d welcome something more direct — could you let me know exactly what you need from me?'
  },
  {
    id: 'e-014', batch: 2, cast: 'tobias', situation: 'messaged on annual leave',
    time: '11:26 AM',
    pre: [{ me: true, time: 'Yesterday at 6:02 PM', text: 'off for the rest of the week!! everything’s handed over 🌴' }],
    trigger: 'Quick one while you’re off, sorry — can you send over the growth tab?',
    genz: 'twin i’m literally in the sea rn can i send it monday 🥹🙏',
    alts: ['bro i’m on a beach. monday?',
           'i’m in the ocean 💀 i’ll send it when i’m back',
           'omg i’m on holiday. can it wait til monday'],
    corporate: 'I’m away on leave at the moment — would it be alright if I sent this across on Monday?'
  },
  {
    id: 'e-015', batch: 2, cast: 'cecilia', situation: 'asked to present to leadership',
    time: '4:07 PM',
    trigger: 'I’d like you to walk the leadership team through this on Thursday. You know it better than anyone.',
    genz: 'WAIT ME?? i’ve never done this before pls help 😭',
    alts: ['me???? i have never presented in my life. help',
           'omg ok 🫠 i’ve genuinely never done this before',
           'wait i’m so scared. can u tell me what to do'],
    corporate: 'I’d be glad to, though I should flag that this would be my first time presenting — I’d be very grateful for some guidance.'
  },
  {
    id: 'e-016', batch: 2, cast: 'nadia', situation: 'handed something you do not understand',
    time: '3:33 PM',
    trigger: 'Going forward I’d like you to own the client relationship on this one.',
    genz: 'LMAOOO me?? idk what i’m doing but i’m down...',
    alts: ['ok!! i have no clue what that involves but sure',
           'me?? 🙃 i’ll do it but i don’t know what it means',
           'yes obviously. also what does that mean'],
    corporate: 'I’m very happy to take this on, though I’ll admit I’m not yet clear on everything it involves.'
  },
  {
    id: 'e-017', batch: 2, cast: 'tobias', situation: 'a deadline you did not know about',
    time: '9:04 AM',
    trigger: 'Just checking this is still landing today.',
    genz: '☠️ wait it’s due TODAY?? i thought friday, i’m on it',
    alts: ['TODAY?? i had friday in my head. starting now',
           'omg it’s today 😵‍💫 ok i’m on it right now',
           'wait today. ok. i thought we said friday'],
    corporate: 'Apologies — I had understood the deadline to be Friday. I’ll get onto it right away.'
  },
  {
    id: 'e-018', batch: 2, cast: 'cecilia', situation: 'you missed a call entirely',
    time: '11:09 AM',
    trigger: 'You weren’t on the client call — everything alright?',
    genz: 'omg i’m so sorry i completely missed it catch me up? 😔',
    alts: ['i am so sorry. it wasn’t in my calendar. what did i miss',
           'omg 🫠 i completely forgot. can u tell me what happened',
           'so sorry!! i missed it entirely. what do i need to know'],
    corporate: 'I’m so sorry, I missed that entirely. Would you mind bringing me up to speed?'
  },
  {
    id: 'e-019', batch: 2, cast: 'nadia', situation: 'a message that is only acronyms',
    time: '1:47 PM',
    trigger: 'Can you get the QBR deck to the PMO before the SteerCo, and flag anything that affects the RAG status?',
    genz: 'fam what is a QBR. i’ve been nodding for 3 weeks',
    alts: ['ok what is a QBR 💀 i’ve been pretending to know',
           'twin i don’t know what any of those letters mean',
           'genuinely what is a PMO. i’ve been too scared to ask'],
    corporate: 'Apologies, could I ask what QBR refers to? I should have raised this sooner.'
  },
  {
    id: 'e-020', batch: 2, cast: 'tobias', situation: 'the fourth deferral of the same decision',
    time: '5:16 PM',
    trigger: 'Good discussion today. Let’s circle back on this next week when we’ve all had time to reflect.',
    genz: 'twin we’ve circled back 4 times 🫠 can we just decide today',
    alts: ['this is the 4th time. can we just pick one',
           'bro 💀 we keep circling back. can we decide now',
           'we’ve had this exact conversation 4 times ngl'],
    corporate: 'We’ve revisited this a few times now — would it be possible for us to reach a decision today?'
  }
];

/* One batch is loaded at a time, so `⌥1`–`⌥9` still reaches almost all of it and a shot
 * batch is never one wrong keypress away. Default is CURRENT_BATCH; `./run.sh dark-b1`
 * brings back an earlier batch and `dark-all` loads every scenario in order.
 *
 * Batch 1 (`e-001`…`e-010`) was filmed 2026-08-22. Leave it exactly as it is: its E-2
 * twins have to reuse the same lines, POV and captions or the pair cannot be read
 * (`FORMAT-TESTS.md` §4). Batch 2 is `e-011`…`e-020`. */
const CURRENT_BATCH = 2;
const HASH = (typeof location !== 'undefined' ? location.hash.slice(1) : '').split(/[-,+]/);
const BATCH = HASH.includes('all') ? null
            : HASH.includes('b1')  ? 1
            : HASH.includes('b2')  ? 2
            : CURRENT_BATCH;

/* Assembled for slack.html. No build step — this runs on load; edit above and reload. */
window.SCENARIOS = SCENES.filter(s => BATCH === null || (s.batch || 1) === BATCH).map(s => {
  const c = CASTS[s.cast];
  const boss = m => ({ from: c.name, initial: c.initial, color: c.color, time: m.time, text: m.text });
  return {
    id: s.id, app: 'slack', situation: s.situation, pov: POV,
    workspace: c.workspace, dm: c.name, dmTitle: c.name, dmSubtitle: c.title,
    thread: [...c.scrollback, ...(s.pre || [])]
      .map(m => (m.boss ? boss(m) : m))
      .concat(boss({ time: s.time, text: s.trigger })),
    genz: s.genz, alts: s.alts, corporate: s.corporate
  };
});
