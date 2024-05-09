local QuestDefinitions = {}

-- Define all quests and their objectives as simple descriptions
QuestDefinitions.quests = {
    ["Repair Equipment"] = {
        title = "Repair Malfunctioning Equipment",
        objectives = {
            {name = "Locate Equipment", description = "Find the malfunctioning equipment using diagnostics."},
            {name = "Gather Materials", description = "Collect necessary materials from storage."},
            {name = "Conduct Repairs", description = "Perform the necessary repairs on the equipment."},
            {name = "Test Equipment", description = "Test the equipment to ensure it is functioning properly."},
        }
    },
    ["Track Supplies"] = {
        title = "Track Missing Supplies",
        objectives = {
            {name = "Audit Inventory", description = "Check current inventory levels against logs."},
            {name = "Interview Crew", description = "Interview crew members about the use of supplies."},
            {name = "Search Supplies", description = "Search for hidden or misplaced supplies."},
            {name = "Update Inventory", description = "Update the inventory system to prevent future discrepancies."},
        }
    },
    ["Analyze Footprints"] = {
        title = "Analyze Mysterious Footprints",
        objectives = {
            {name = "Document Locations", description = "Use a map to mark where footprints have been found."},
            {name = "Collect Samples", description = "Take samples of the snow for further analysis."},
            {name = "Follow the Trail", description = "Track the footprints to their origin."},
            {name = "Analyze Data", description = "Use lab equipment to analyze the footprints for any traces."},
        }
    },
    ["Examine Ice Cores"] = {
        title = "Examine Disturbing Discoveries in Ice Cores",
        objectives = {
            {name = "Extract Ice Cores", description = "Perform drilling operations to gather new ice cores."},
            {name = "Prepare Samples", description = "Prepare slides from ice cores for examination."},
            {name = "Microscopic Analysis", description = "Conduct microscopic analysis to identify anomalies."},
            {name = "Record Findings", description = "Document and report findings to the research lead."},
        }
    },
    ["Decode Cryptic Messages"] = {
        title = "Decode Cryptic Messages",
        objectives = {
            {name = "Capture Signal", description = "Adjust the radio equipment to capture the cryptic signals."},
            {name = "Transcribe Messages", description = "Write down the encrypted messages."},
            {name = "Decrypt the Code", description = "Use cryptographic tools to decode the messages."},
            {name = "Analyze Message Content", description = "Determine the significance or origin of the decoded messages."},
        }
    },
    ["Inspect Sealed Off Areas"] = {
        title = "Inspect Sealed Off Areas",
        objectives = {
            {name = "Find Entry Points", description = "Locate all potential entry points into the sealed areas."},
            {name = "Bypass Locks", description = "Solve puzzles or find keys to open locked doors."},
            {name = "Investigate the Interior", description = "Explore the area and collect any unusual items or data."},
            {name = "Document Findings", description = "Take photos or notes on any abnormalities or notable objects."},
        }
    },
    ["Document Wildlife Behavior"] = {
        title = "Document Wildlife Behavior",
        objectives = {
            {name = "Observe Wildlife", description = "Spend time watching the behaviors of local wildlife."},
            {name = "Record Behaviors", description = "Use video or audio equipment to capture unusual behaviors."},
            {name = "Analyze Patterns", description = "Look for patterns or triggers for the behavior."},
            {name = "Report to Environmental Team", description = "Provide footage and findings to the environmental research team."},
        }
    },
    ["Assess Distorted Communications"] = {
        title = "Assess Distorted Communications",
        objectives = {
            {name = "Check Communication Equipment", description = "Inspect and test all communication devices for faults."},
            {name = "Identify Sources of Interference", description = "Use equipment to detect sources of signal interference."},
            {name = "Restore Communication Lines", description = "Make necessary adjustments or repairs to clear up communications."},
            {name = "Confirm System Stability", description = "Ensure that communication is restored and stable across various channels."},
        }
    },
}

return QuestDefinitions
