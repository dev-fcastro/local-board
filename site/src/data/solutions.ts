export interface Solution {
  slug: string;
  label: string;
  title: string;
  description: string;
  heading: string;
  intro: string;
  problem: string;
  benefits: { title: string; text: string }[];
  workflow: string[];
}

export const solutions: Solution[] = [
  {
    slug: "offline-workshops",
    label: "Workshops",
    title: "Offline whiteboard for workshops | Local Board",
    description: "Run brainstorming sessions without depending on Wi-Fi. Capture ideas on a local whiteboard and export the board when you're ready to share it.",
    heading: "Keep the workshop moving when Wi-Fi stops.",
    intro: "A connection should not decide whether your team can think together. Local Board runs on your computer, saves the board there, and lets you export the result afterward.",
    problem: "In a room with unreliable internet, a browser whiteboard can interrupt the session right when ideas are flowing. A local board gives you a place to keep drawing and organizing the conversation.",
    benefits: [
      { title: "Start without a sign-in", text: "Open the desktop app and create a board. No account is required." },
      { title: "Capture as you go", text: "Use pen, shapes, arrows, text and sticky notes to collect ideas in one place." },
      { title: "Leave with a file", text: "Export a PNG or SVG, or keep the editable board file for another session." },
    ],
    workflow: ["Create a board before the session.", "Capture and group ideas as the discussion unfolds.", "Export or save the board when the team is ready to share it."],
  },
  {
    slug: "software-architecture",
    label: "Software architecture",
    title: "Software architecture diagrams offline | Local Board",
    description: "Sketch software architecture on an offline whiteboard. Arrange components, connect ideas and keep editable diagrams on your own computer.",
    heading: "Map a system before the details get lost.",
    intro: "A quick diagram can make a design discussion concrete. Local Board gives you a local canvas for components, relationships and notes, even when you are away from a connection.",
    problem: "Architecture conversations often begin as scattered notes. When the diagram lives only in a meeting tool, it can be hard to return to the same editable thinking later.",
    benefits: [
      { title: "Make the structure visible", text: "Place software components and connect them to explore a system's shape." },
      { title: "Keep context beside the diagram", text: "Add text and sticky notes for decisions, questions and next steps." },
      { title: "Revisit the draft", text: "Boards save locally, so you can reopen and refine a design." },
    ],
    workflow: ["Lay out the main services or components.", "Connect dependencies and annotate open questions.", "Save the editable board and export an image for discussion."],
  },
  {
    slug: "network-diagrams",
    label: "Network diagrams",
    title: "Network architecture diagrams offline | Local Board",
    description: "Draft network diagrams on your computer without an account or live connection. Organize components and export a visual for review.",
    heading: "See the network before you change it.",
    intro: "Use a visual draft to discuss devices, services and connections. Local Board keeps that draft on your computer and available when the network itself is unavailable.",
    problem: "A network planning session may happen where connectivity is limited. The diagram still needs to be available, editable and easy to share once the work is done.",
    benefits: [
      { title: "Work without the network", text: "The desktop canvas does not need a live connection to draw." },
      { title: "Arrange the pieces", text: "Use network components, lines, arrows and labels to outline a topology." },
      { title: "Share a visual copy", text: "Export the diagram as PNG or SVG while keeping the original board editable." },
    ],
    workflow: ["Place the main devices and services.", "Draw connections and label important paths.", "Review the draft, then export a copy for the team."],
  },
];
