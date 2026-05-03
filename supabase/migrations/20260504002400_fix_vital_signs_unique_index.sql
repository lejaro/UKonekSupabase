-- Fix the partial unique index on vital_signs so it can be used by ON CONFLICT.
-- Standard UNIQUE indexes in PostgreSQL allow multiple NULL values, so the WHERE clause is not needed for uniqueness.

DROP INDEX IF EXISTS public.uq_vital_signs_queue_ticket;

CREATE UNIQUE INDEX uq_vital_signs_queue_ticket
  ON public.vital_signs (queue_ticket_id);
