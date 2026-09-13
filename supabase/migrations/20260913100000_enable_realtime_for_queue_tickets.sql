-- Enable Supabase Realtime for queue_tickets table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'queue_tickets'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.queue_tickets;
  END IF;
END $$;

-- Set replica identity to full so that update payloads contain old and new records
ALTER TABLE public.queue_tickets REPLICA IDENTITY FULL;
