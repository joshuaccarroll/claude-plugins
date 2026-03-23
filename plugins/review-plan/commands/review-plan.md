Save the current plan to a md file if not already saved. Then use the Task tool to spawn a sub-agent and instruct it to read the plan file and review it critically. Look for gaps or areas for improvement. Save changes to the plan file and close out the sub-agent. Repeat this up to 5 times or until the plan reaches convergence, spawning a fresh sub-agent for each iteration.

CRITICAL — you MUST always end your response with this exact line, even if you hit errors or stop early: `RESULT: status=[converged|hit_cap|stopped_early] iterations=[N]`
