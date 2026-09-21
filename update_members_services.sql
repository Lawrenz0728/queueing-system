-- Update services for Members Services Queueing System
-- Run this in Supabase SQL Editor.

-- Deactivate previous services
UPDATE public.queue_services
SET is_active = false
WHERE service_code NOT IN (
  'LOANS_MEMBERSHIP',
  'VISA_ENCODING',
  'NOTARIAL',
  'PHOTOCOPY'
);

-- Add the four requested services
INSERT INTO public.queue_services
  (service_code, service_name, description, is_active)
VALUES
  ('LOANS_MEMBERSHIP', 'Loans and Membership', 'Loans and membership services', true),
  ('VISA_ENCODING', 'Visa Encoding', 'Visa encoding services', true),
  ('NOTARIAL', 'Notarial', 'Notarial services', true),
  ('PHOTOCOPY', 'Photocopy', 'Photocopy services', true)
ON CONFLICT (service_code)
DO UPDATE SET
  service_name = EXCLUDED.service_name,
  description = EXCLUDED.description,
  is_active = true;
