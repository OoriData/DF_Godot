This document will serve as a flowing state of things needed in the project,  what resources are needed for each task.

UI : 
- [ ] Nav Bar / User info bar ( Resources :  Documentation Home,  UserInfoDisplay)
	- [ ] Fix blocked art issue,  right now when we are in a wide screen the art tiles have curved edges and this leads to small gaps between the tiling for the art.
	- [ ] The Style for the nav bar is really Blocky and not great to look at,  suggjested ways to adjust:
	      **The core issues:**
		1. **Inconsistent visual weight** — "FakeIce" and "Options" look like the same type of element as "Feedback", but they serve different purposes (brand vs navigation vs action). Nothing is visually differentiated by role.
		2. **The money display feels stranded** — `$994,658,831` is floating in the center with no container, no icon, no label. It reads as an afterthought rather than a key game stat. Players' eyes don't know to look there.
		3. **"Select Convoy ▼" is too plain** — It's a critical game action but looks like a browser dropdown. It doesn't feel like it belongs to the same game world as the pixelart map.
		4. **The navbar itself has no real presence** — It's a thin dark strip that competes with the dark map tiles. There's no separation or visual grounding between the HUD and the play area.
		5. **No visual hierarchy or grouping** — Left, center, and right elements all have the same treatment, so the eye doesn't know what's primary.
		
		**Concrete suggestions:**
		
		- **Add a subtle bottom border or drop shadow** to separate the navbar from the map — even 1-2px of a lighter color does a lot
		- **Give the money a coin/dollar icon** and maybe a slight background pill or bracket so it reads as a "stat widget"
		- **Style "Select Convoy" as a game button** — give it a border, a pixel-art-ish style, or a colored accent so it feels interactive and important
		- **Group elements intentionally** — brand on the left, game stats in the center, actions on the right — and add a little spacing/padding between groups
		- **Differentiate "Feedback"** — if it's a bug/feedback button, consider making it smaller, subtler, or icon-only so it doesn't compete with navigation
	
- [ ] UI scale,  Text sizes and mobile translation