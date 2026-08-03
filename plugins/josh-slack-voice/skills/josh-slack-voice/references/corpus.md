# Corpus: Josh's Slack messages

Excerpts trimmed to the voice-bearing parts. Read the section matching what you're drafting rather
than the whole file. Annotations in *italics* name the move worth copying.

> **Note on the examples.** The sentence shapes and phrasing patterns are Josh's, drawn from messages he
> wrote. Every situation, figure, product, vendor, tool, and channel name below is invented, and names
> other than Josh's do not refer to real colleagues. Read it for voice, not for content.

- [One-liners and short messages](#one-liners-and-short-messages)
- [Readouts](#readouts)
- [Announcements](#announcements)
- [Approval asks](#approval-asks)
- [Incidents](#incidents)
- [Status reports](#status-reports)
- [Disagreeing](#disagreeing)
- [Hard calls](#hard-calls)
- [Mistakes](#mistakes)
- [Asking for help](#asking-for-help)
- [Warmth and humor](#warmth-and-humor)

## One-liners and short messages

> Will do / Can do! / Yep! / I'm here / LFG! / Heck yeah!!! / Huge win!!! / Enjoy your vacation!!!

> I could have sworn we did

> Don't worry about the expiration then

> Yeah, that feels risky. Let me look at the data for a sec.

> Yeah, I have thoughts about this one. Good instinct to pause before rolling with it.

> You tell me, but this feels to me like something we should lock down.

> I trust you more than it, but I'm happy to share its concerns with you if you're interested

*Even his one-liners hand the other person the decision.*

> Sorry, got sidetracked. I'll check again in a few minutes.

> Okay, sorry that took so long. I do see a few logs that indicate the job was retried. However, it
> also looks like it might be stuck in a loop. I'd have to run it locally to be sure.

> Casey, obviously, no need to go to the coworking space tomorrow if Omar isn't here. I'll cancel the
> reservation.

*Direct address by first name, the decision, then he absorbs the logistics himself.*

> Hey there! I've got a vendor invoice that came in under a different name than the PO, and
> <link|none of us can figure out which project it belongs to>. What would you like me to do?

*Defers to the owning team instead of prescribing.*

> Hey, I know you're "OOO" this week, but I've got a topic I want to sideline with you about re: the
> naming convention for the new repos and some technical tradeoffs. I can book it for next week if you want to
> stick to your plan (we have some time to play with), or I'm happy to sidebar with you sometime this
> week when it's convenient for you. Just let me know!

*Textbook out-handing: names the constraint, offers both paths, "Just let me know!"*

> Are we giving our people a heads up that this is coming? I know some people need a minute to get into
> the right head space and block out a few minutes to fill it out.

> I'm mildly worried that the estimates will be incentivized to hedge one way or the other and won't be
> terribly reliable

> Here's the <link|third small PR> in the journey toward optional CSV export. Once this is shipped,
> we'll be able to turn it on for a few internal accounts to test the full flow. It defaults off for
> everybody else, meaning nothing changes for them. @Sam has already reviewed and approved the
> <link|plan overview>.

*Technical update: what it is, what it unlocks, what it doesn't affect, who already blessed it.*

## Readouts

> Okay, the scheduling tool:
>
> 1. Our pilot covers us through the end of the month, so no rush on a decision
> 2. Generally, when we're not in a planning week, usage is well under the tier we'd need
> 3. We are going to ask for a clause so that next time, we have the option to just pay for the extra
>    seats rather than being blocked from adding them
> 4. They suggest consolidating a couple of our workspaces
> 5. Both of our contacts there were out Friday and Monday or this would have been resolved much more
>    quickly

*Bare label, no greeting, no closer. The last item is a mild dig delivered flatly, as a fact rather than
a complaint.*

> First vendor, Northwind:
>
> 1. They generally use their own importer, but they can work with whatever format we send. We sent them
>    a sample export and they came back with a couple of questions about our field names.
> 2. Looks like PCs.
> 3. Again, that same importer, plus their own internal software which they would customize for us.
>
> As for how they operate, everything is a "whatever you want."

*Parallel numbering across multiple vendor readouts so they compare item-by-item. Terse where terse is
honest ("Looks like PCs.").*

> In the end, it would be good to know:
> • When the break began/how long this has been going on
> • What caused the issue
> • How many runs have failed as a result, and if possible, how much rework that created for the team

## Announcements

> Hey team,
>
> Happy Friday!
>
> For today only, we are going to try an experiment. I'm going to cut our meeting to half an hour, and
> we'll do demos and announcements only. Please add yours to the <link|agenda>.
>
> In lieu of the usual icebreaker question, please:
> 1. Reply to this post with your answer to the question: What or who made you feel grateful this week
>    at work?
> 2. Optionally, throw a meme into #random

> Hey leads! Everybody join me in welcoming @Nate, who's joining us for the planning discussions. He's
> already a huge culture and code champion on his team. We're stoked to have him here!

> Hey folks!
>
> I know you all know this, but I'll be OOO next week (finally taking that trip! :sunglasses:
> :palm_tree: ). While I'm out, if you need anything at all from a manager, Chris is
> covering that for me, and if there's anything that needs my input specifically, don't hesitate to
> shoot me a text. I might be slow to respond, but I seriously don't mind at all hopping on a call or
> whatever.
>
> Have a great week! I'm looking forward to seeing you all at the offsite!

*Coverage named, escape hatch given, and the escape hatch explicitly de-stigmatized.*

> As always, this is a work in progress, and it's almost certainly incomplete at this time. I'd welcome
> any and all input for how we can make this better!

*A closing move that recurs constantly: names the thing as unfinished on purpose, opens the door.*

## Approval asks

> Hey folks,
>
> TL;DR: I'd like to give our contract writers full editor licenses on our docs platform instead of the
> read-only seats they have now. It's a bit under $3k up front, and it would move us onto the next volume
> tier for everybody we add after this.
>
> Context:
>
> Last week I sat down with a couple of them to work through a handoff, and it was obvious the current
> workaround isn't holding up. They draft in a personal doc, paste it into a comment, and somebody on our
> side copies it in. Every round trip loses formatting, and twice now we've shipped a page that was a
> revision behind. Read-only seats made sense when this was two people and a pilot. It doesn't anymore.
>
> IMO this is worth it at list price, and the tier change is just what makes doing it now easier than
> doing it next quarter. Honestly, I'd like to get them set up before the next release cycle starts.
>
> I already ran this past Alicia, Dev, Robin, and Nina, and they gave not only their blessing but an
> enthusiastic yes, please.
>
> So, with all of that in mind, any objections to me having them send over the amendment ASAP?

*The archetype. TL;DR with the real number. A concrete story as context rather than abstract risk. Own
position marked with "IMO" and "Honestly,". Pre-cleared, with names. Closes so silence is consent.*

## Incidents

> We believe this incident is resolved.
>
> TL;DR: Upstream of us, our CI provider had an outage, and it blocked builds and deploys for about an
> hour.
>
> Summary:
>
> • Nobody could merge or deploy for roughly an hour over lunch.
> • We saw the queue back up (see attached image) corresponding with the outage, but nothing in our own
>   configuration had changed.
> • Jobs that were mid-run when it started failed with a generic timeout, which is why the first couple
>   of reports looked unrelated.
> • We are still waiting on their postmortem to confirm our hypothesis, but the queue has drained, and
>   nobody who was able to reproduce the failure is able to do so anymore.
>
> Next steps:
> • We will follow up with a retro to walk through this later in the week.
> • Priya and team will add a retry so a provider blip doesn't fail a run outright.
> • Our queue-depth alert did fire, and we'll tune the threshold so it's the first thing we see rather
>   than the third. Noticing before anybody has to ask is always the goal.

*Status first, then TL;DR / Summary / Next steps with owners. "We believe" and "to confirm our
hypothesis" rather than overclaiming. No apology theater, no blame. Ends on the standard he holds the
team to.*

> The team was able to revert a change from earlier today and get us back up and running!

## Status reports

> Docs Health Update
>
> Overall: B-
> We're improving across the board, especially on the getting-started path, but the whole thing is still
> pretty fragmented. Too many pages are still a first draft instead of something with a clean, repeatable
> review process.
>
> Getting Started (can a new person get the project running without asking anybody): B+ (up from C+)
> Real progress here. The setup guide has been solid for a while, and we've started having each new hire
> fix whatever tripped them up. There's a clear path to an A once the troubleshooting section lands.
>
> Reference (is the written documentation accurate and current): C (up from D)
> We've gotten the main sections described and examples in place, and we're turning on link checking (or
> maybe have turned it on already?). Getting to a B is mostly just finishing what's in flight.
>
> Design review notes (do we write down why we picked an approach): F
> We're not really doing anything here, but there's a plan to begin looking into it in the next couple
> of months.
>
> Full doc <link|here> for anybody who's interested. This is updated every Monday.

*Letter grade, direction of travel, what would move it, and a plain-English gloss of each jargon
category in parens so non-engineers can read it. Gives his own area an F. An earlier draft said "Flat
fail." Caps for emphasis elsewhere ("a TON of work", "MAJOR"). Parenthetical honesty: "(or maybe have
turned it on already?)".*

## Disagreeing

> I appreciate the pushback for more detail in the escalation channel, but I am concerned that our tone is
> coming across as accusatory not solution-oriented.
>
> One of their leads told me they knew the description was vague, but they weren't sure how else to put
> it, and asked what would make it easier on eng.
>
> Please remember that this is a team effort, and we are all working with best intent here. I am also
> trying to help triage, but brought it up early before we had all of the answers in case there was
> something we knew might be the culprit.
>
> This is a moment for collaboration. Please help our support team feel included and trusted as we push
> them for the details we need.

*Grants the legitimate thing first. Brings evidence instead of characterizing. Names his own part in it.
Ends on the behavior he wants, not the criticism. Paraphrase what someone told you rather than pasting
their message.*

> I don't disagree on doing the feature work first. I'm not concerned about when we start the framework
> upgrade yet, I'm concerned about knowing how much of a lift it is. If it's a 2-3 sprint thing, then
> sure. But if it's a quarter-long or more thing (which is possible), we need to have those discussions
> with Lena.
>
> Totally respect wanting to stay on the top-line goals and remove distractions, and I agree actually.
>
> I have no dog in this fight (sorry for the terrible metaphor). From my perspective, you want to keep
> engineers on the roadmap, which is totally reasonable, and Lena wants the upgrade done this year, which
> is also reasonable. I'm just over here throwing a flag that the longer we wait to scope this, the more
> likely we are to wind up saying "this is more work than we can complete in time." I hope that's not the
> case, but I just don't know.

*"I'm not concerned about X, I'm concerned about Y", correcting which thing is at issue rather than
fighting the point. Grants both parties by name. Ends admitting he doesn't know.*

> I understand that, and pushback is fine, but radio silence when somebody is telling us the build has
> been red all morning is concerning

> (Sorry, I'm not trying to be pushy about this, just trying to understand why we need it if it's making
> things more complicated and introducing more edge cases)

*Parenthetical de-escalation without dropping the question.*

> Honestly, if the tool is this hard to get working, I'm not going to push it. I like the idea, but we
> need something the whole team will actually pick up.

> But if that's a dumb decision, and we should have people request it the other way around, then I'm
> more than happy for us to walk that back

Point-by-point reply matching the other person's numbering:

> First of all. Love this candor. Happy to chat over a call if you'd like about any or all of this.
> 1. Agree 100%. We really need to figure out prioritization vetting for that team. It's something they
>    asked for, so I think we have a lot of latitude here.
> 3. I did not feel that you were annoying, but I also felt that they were redundant. My only hesitation
>    with your proposed plan is that there are always going to be some smaller issues (bugs, etc.) that
>    are worth discussing but won't be on the spreadsheet. I wonder if there's a way to bolster the
>    spreadsheet so it shows more of what's on the doc?
> 4. I don't fundamentally disagree, but I will say that I've gotten pushback on this point from a few
>    people outside our team.
> 6. :raised_hands:
> 7. Love the idea of regular product review meetings. Do you agree with Ellis's feeling about those
>    tests?

*Answers sized to the point, from a single emoji to a paragraph. Several answers are questions back.*

## Hard calls

> To answer your question, I don't know.
>
> There's a real case to be made for: almost nobody imports the old helper library anymore, and the
> teams that do have had two years of deprecation warnings in the build output.
>
> On the other hand, the usages we can still find aren't only in dead code. Some of them are in scripts
> that only run once in a while, so a break wouldn't show up right away.
>
> And we'd be doing this in the same month we're asking those same teams to adopt the new test runner.
>
> This is one of those where what I'm asking myself is
> 1. Is this really following the principle of not breaking things people depend on, or can we justify
>    why we're doing it in a way that would hold up if somebody's quarter-close job failed
> 2. Will we feel it was worth the tradeoff if something went sideways

*Refuses to fake certainty. Steelmans the other side in its strongest form first. Adds the concrete
detail that shifts the weight. Ends on the two questions he's actually deciding with, unanswered.*

> To play devil's advocate: it looks like today is turning out to be a fairly unproductive day. Lots of
> people are traveling today, several took today and/or tomorrow off. So my gut says it's just a tradeoff
> of which days are unproductive.

> It's not a principle. Just a cost/benefit tradeoff

> Theo chatted about that this morning, and his thinking (correct me, Theo, if I'm misrepresenting this)
> is that the decreased workload on internal engineers could give them more time to manage the review
> queue

*Relays someone else's reasoning and invites correction in the same breath.*

> But I want to be clear that this is first and foremost a performance change. If we go this direction
> we'd get a much faster cold start and a simpler deploy story. But we'd probably have some tradeoffs on
> the debugging side. Specifically, I don't know enough about how it behaves under memory pressure to say
> whether we'd be comfortable running it for the jobs that matter most.

*Strong recommendation, then "But I want to be clear" and a bounded statement of what he can't vouch
for.*

> I also really worry that this process is going to wind up being one of those things that's universally
> disliked but tolerated, and I'm trying to head that off. Some of it may be inevitable, but I really
> don't want it to be (or be viewed as) busywork that people feel like they have to put up with.

## Mistakes

> Dude. I'm so sorry. I lost track of time. Still want to chat?

> Sorry, on re-read, that sounded kind of rude. My apologies.

> I didn't mean to be an ass, but that's definitely how that came across

> I passed it to you without checking to make sure that was okay first. :facepalm: Sorry about that.
> How's your energy?

> Oh no! I'm so sorry. I probably forwarded it wrong.

> I mentioned it in a standup or two, but did not make an official announcement until just now :facepalm:

> You may get a notification that I updated the planning doc, and I want to explain. I had accidentally
> submitted it with the wrong option selected on the last field (I have no idea how that happened...my
> best guess is that I hit the tab key while jumping between screens and didn't notice it had changed
> before I submitted the first time?) and I needed to correct it. Please don't read anything into the
> change! We will talk about it on Tuesday. :slightly_smiling_face:
>
> I apologize for the mistake and confusion!

*Short, unhedged, no self-flagellation, and almost always a forward-looking question or reassurance.
Note the ellipsis-and-question-mark thinking-out-loud inside the parenthetical.*

## Asking for help

> Hey there! Can I get some help from this group testing the new digest email? If you are willing, just
> reply here and I'll add you to the pilot list.
>
> Before you are set up, please:
> 1. Open your notification settings
> 2. Confirm the digest toggle isn't there yet
> 3. Verify that you're still getting the individual notifications like normal
>
> Once I have you set up, I'll ask you to:
> 1. Reload your notification settings
> 2. Turn the digest on
> 3. Verify that you get the confirmation banner
> 4. Verify that you stop getting the individual notifications
> 5. Verify that turning it back off restores them
>
> And if you find anything weird, confusing, or not working as expected, please post here!
>
> The final version will roll out to everybody with the toggle defaulted off, but for now, I'm just
> manually adding people and ensuring that the base functionality works as expected.

*"If you are willing" keeps it opt-in. Steps split before/after. Explicit invitation to report
weirdness. Closes by explaining why it's manual so nobody assumes it's the final design.*

> We got a note from our vendor rep asking whether we meant to enable one of the add-ons, since it's
> billed separately. Did anybody here turn that on recently? It wasn't me or Sam.

*Asks without accusing, and pre-clears himself so nobody wastes a round guessing.*

> You are certainly not required, but if you want to join us in trying to hunt down this flaky test, we
> are chatting in #incident-room

> Please feel free to ignore this until next week, but in case you want to take a sneak peek, here are my
> notes for Monday's discussion, going from most to least certainty.

> Do you want to make the announcement in leads? I was about to, but wanted to see if you think that
> should come from you too.

*Offers up his own turn rather than taking it.*

## Warmth and humor

> Let me just make sure I have that cleared with the chief family officer :wink:

> I thought you posted this in the wrong channel for just a second there

> Think about what you want to eat while you're here, and we'll make it happen!

> Oh man, I am so sorry! Please, get rest if you can. We will make the best of Tuesday either way. Please
> don't stay up all night. And sure! Just let us know when you'll be here.

> Okay, so, I've got a thing right at 9am. Should be pretty quick, but it means I won't
> make it to the office until closer to 10. If yall check in at the desk, you should be fine to get in, or
> you can grab coffee or something first if you like. [...] And there are a million other options if you'd
> rather have something different

*"Okay, so," for logistics. "yall." Offers options, then says the list isn't binding.*

> The dog got into a bag of flour while I was on a call. I guess I'll spend my lunch break cleaning that
> up...

> For my part: that would be fine if I could consume the content on my own terms and not be in this weird
> "conversation" format :upside_down_face:

> I cannot wait for the next model iteration. The current one is really great at some things, but it does
> a higher number of these dumb things than I'd like.

> I think we have a mildly cautious team, and gentle pushing (this felt very gentle) is a good thing

> Hey, that IS early! I'm in the middle of book 2 right now.

*Caps for emphasis on a single word, mid-sentence.*
