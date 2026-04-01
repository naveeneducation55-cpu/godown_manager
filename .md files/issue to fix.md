You are working on a production-grade inventory management system (Flutter + Supabase).

Focus on correctness, edge cases, and clean architecture. Do NOT rush into code — first understand, validate, then implement.

---

TASK 1: INVENTORY VALIDATION LOGIC (CRITICAL FIX)

Problem:

* Currently, the system allows transferring more quantity than available.
* Example:

  * Source location has: 10 pcs
  * User tries to move: 15 pcs
    → This is logically incorrect but currently allowed.

Required Fix:

* Add strict validation before movement is processed.

Expected Behavior:

* Prevent transfer if requested quantity > available quantity
* Show clear error message to user

UI Requirement:

* Display error message at bottom of screen (global/general message, not just field-level)
* Message example:
  → "Transfer quantity exceeds available stock"

Backend Requirement:

* Validation MUST exist in:

  1. Frontend (for UX)
  2. Backend / DB layer (for data integrity)

Edge Cases to Handle:

* Null or empty quantity
* Negative values
* Zero transfer attempt
* Concurrent updates (stock changed during operation)

---

TASK 2: SAVE BUTTON NOT WORKING (BUG FIX)

Problem:

* When:

  * Adding an existing item
  * Checkbox in movement section is selected
  * Form is filled
    → Save button does NOT work

Expected Behavior:

* Save button should:

  * Validate inputs
  * Trigger correct logic path
  * Proceed with movement/update

What to Investigate:

* Checkbox state handling
* Form validation logic
* Conditional rendering / enable-disable logic
* Event binding / onPressed trigger
* State management issue (possible rebuild or state not updating)

Debug Approach:

1. Trace checkbox state flow
2. Check if form validation is blocking submission
3. Verify if button is disabled conditionally
4. Ensure correct function is being called
5. Check async operation handling

---

IMPLEMENTATION RULES:

* Do NOT rewrite entire files
* Identify minimal required changes
* Follow existing architecture
* Maintain clean separation (UI / logic / backend)

---

OUTPUT FORMAT:

1. Understanding of issue
2. Root cause analysis (for bug)
3. Proposed fix (step-by-step)
4. Code changes (minimal and precise)
5. Edge cases handled

---

IMPORTANT:

* If anything is unclear → ASK before coding
* If multiple approaches exist → suggest best one with reasoning
* Focus on correctness + scalability, not just quick fixes

---

Start by analyzing both issues and asking any missing questions.
