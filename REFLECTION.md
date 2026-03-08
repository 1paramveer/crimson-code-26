# HealthCam – CrimsonCode 2026

**Author:** Srishanth Surakanti  
**Hackathon:** CrimsonCode 2026 
**Project:** Camera based biometric monitoring with conversational AI support

---

## Project Summary
HealthCam is an experimental iOS prototype that explores whether everyday smartphone hardware can be used for quick physiological feedback. Using the device’s front camera, the system estimates signals such as heart activity and breathing patterns through remote photoplethysmography (rPPG).

The application pairs this sensing layer with a conversational voice interface that can respond to the user's physiological state and provide guided feedback during stressful moments.

---

## Implementation Highlights

**Camera Driven Biometrics**  
Instead of external devices or wearables, the system relies entirely on the phone camera for signal extraction. This allowed the prototype to focus on accessibility and immediate usability.

**Processing Control Logic**  
Part of the work involved managing the biometric processing lifecycle so that downstream features only activate once reliable signal capture begins. This coordination prevented unnecessary triggers while the camera system was still calibrating.

**Real Time Interaction Layer**  
The biometric readings were connected to a conversational audio component that provides spoken guidance to the user, allowing the experience to function without requiring visual attention.

---

## My Role (Srishanth Surakanti)

My work primarily centered on the **system integration layer** of the prototype:

- Coordinating the biometric data pipeline with the application logic  
- Implementing safeguards for the signal processing lifecycle so dependent features only activate when valid readings are available  
- Supporting the integration of the voice interaction component with the physiological monitoring flow  
- Assisting with testing and ensuring the demo remained stable under hackathon conditions

---

## Development Context

This project was created during a **24-hour team hackathon** environment. Development occurred collaboratively across shared systems while components were being merged and tested rapidly. Because of this workflow, some code contributions were committed to the repository by teammates during integration stages.

---

## Reflection

The project demonstrated how quickly a concept combining **computer vision sensing and conversational interfaces** can be turned into a working prototype. It also highlighted the engineering trade offs involved when building reliable systems under strict time constraints.

Future iterations could improve robustness by introducing environment aware camera guidance and refining how physiological signals are interpreted before generating responses.
