# App Review & Recommendations (Simplified Client Guide)

This guide translates the technical issues found in the 3D scanning app into simple, everyday terms. It explains why the app sometimes fails to crop faces or slows down, and what we need to do to fix it.

---

## Issue 1: "The Disappearing To-Do List" (The 3D Model Loading Bug)
*   **What is happening:** When the app loads the scanned 3D model to find the face, it tries to move all the pieces of the model into a processing folder. However, it does this while looking at the list of pieces. As soon as it moves a piece, that piece disappears from the original list, causing the app to skip every second piece on the list.
*   **Why it matters:** The app only loads about half of the 3D model (or misses it entirely). This makes the face look broken or invisible to the cropping tool.
*   **The Fix:** We need to make a copy of the list first, and then move the pieces one by one using the copy, so nothing gets skipped.

---

## Issue 2: "Taking Photos in a Blinding White Room" (Face Detection Failures)
*   **What is happening:** To find the patient's chin and neck, the app takes a quick snapshot of the 3D model. However, it takes this photo against a bright white background with strong, flat studio lights. If the patient has a light skin tone, the face blends into the background.
*   **Why it matters:** The "artificial intelligence" (Vision tool) cannot see where the face ends and the background begins. It fails to find the face and skips cropping entirely, uploading the raw scan including the surrounding walls/body.
*   **The Fix:** We should change the camera snapshot background to a contrasting color (like dark grey) and adjust the lighting so the face stands out clearly.

---

## Issue 3: "Running a Computer inside a Phone Screen" (Slow 3D File Conversion)
*   **What is happening:** The 3D scanner generates one file format (`OBJ`), but the website needs a different format (`GLB`). To convert it, the app opens a hidden web browser inside the phone and uses web-based code to translate it.
*   **Why it matters:** Web browsers inside apps are slow and use a lot of memory. If a patient scan is detailed, the phone might run out of memory and crash.
*   **The Fix:** We should translate the files using the phone's native system directly, or let our secure database server handle the translation instead of forcing the phone to do it.

---

## Issue 4: "Reading a Whole Book in One Gulp" (Slow Performance on Big Scans)
*   **What is happening:** When cutting off the neck/body of the scan, the app reads the 3D file by loading the entire file into the phone's memory all at once.
*   **Why it matters:** If the scan is very large, loading the whole file at once makes the phone freeze or lag.
*   **The Fix:** We should change the code to read and process the file line-by-line (like reading a book page-by-page instead of trying to memorize the whole book at once).
