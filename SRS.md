# Draft SRS Contract

This section defines the development phase plan, project pricing alignment, and post-service agreement terms.

###Development Phase (Phases, Timeline, Deliverables)

Total duration: 4 months (16 weeks). The timeline may shift with approved change requests.

Phase 1: Discovery and Planning (Weeks 1-2)
- Activities: stakeholder interviews, requirements confirmation, scope lock, risk assessment.
- Deliverables: approved SRS, project plan, initial backlog.

Phase 2: Architecture and Design (Weeks 3-4)
- Activities: data model finalization, API/RPC design, UI/UX wireframes.
- Deliverables: architecture decision record, ERD baseline, UI wireframes.

Phase 3: Core Build (Weeks 5-10)
- Activities: Supabase schema and RPCs, Edge Functions, web and mobile core flows.
- Deliverables: functional modules (auth, appointments, queue, consultations, inventory, announcements, feedback).

Phase 4: Integration and System Testing (Weeks 11-13)
- Activities: end-to-end testing, RLS validation, performance tuning, bug fixes.
- Deliverables: test reports, defect log resolution, release candidate build.

Phase 5: UAT and Deployment (Weeks 14-16)
- Activities: user acceptance testing, training, deployment preparation.
- Deliverables: UAT sign-off, deployment checklist, production release.

###2 Project Pricing (Budget Allocation)

The budget is aligned with procurement categories and system scope. Allocation is expressed as percentages of the total approved project cost.

- Human resources (analysis, design, development, QA, project management): 60%
- Subscriptions (Supabase plan, email/OTP services, monitoring): 12%
- Hardware (test devices, minimal onsite equipment): 8%
- Miscellaneous (training, contingency, documentation): 20%

Any adjustments to allocation require written approval and documented change request.

###3Post Service Agreement (Maintenance and Support)

Support period: 12 months after production deployment, renewable by mutual agreement.

Maintenance scope:
- Corrective maintenance: bug fixes for production defects.
- Adaptive maintenance: minor updates for platform or dependency changes.
- Preventive maintenance: security patches and RLS policy reviews.

Support terms:
- Support hours: Monday to Friday, 9:00 AM to 6:00 PM local time.
- Response times: Critical 4 hours, High 1 business day, Medium 3 business days, Low 5 business days.
- Delivery: fixes deployed in scheduled maintenance windows unless critical.

Exclusions:
- Major feature additions, third-party integrations, or scope expansion.
- Onsite hardware maintenance and network provisioning.

Renewal and termination:
- Renewal requires a written agreement 30 days before expiration.
- Either party may terminate with 30 days written notice, with fees prorated to work completed.
