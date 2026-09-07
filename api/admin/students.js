const crypto = require('crypto');
const { createClient } = require('@supabase/supabase-js');

function sign(value) {
  return crypto.createHmac('sha256', process.env.ADMIN_SESSION_SECRET || '').update(value).digest('base64url');
}
function parseCookie(header) {
  return Object.fromEntries((header || '').split(';').filter(Boolean).map(x => {
    const i = x.indexOf('=');
    return [x.slice(0, i).trim(), decodeURIComponent(x.slice(i + 1).trim())];
  }));
}
function isAdmin(req) {
  const t = parseCookie(req.headers.cookie).admin_session || '';
  const [p, s] = t.split('.');
  if (!p || !s || !process.env.ADMIN_SESSION_SECRET || s !== sign(p)) return false;
  try {
    const data = JSON.parse(Buffer.from(p, 'base64url').toString());
    return data.exp && Date.now() < data.exp;
  } catch { return false; }
}
function db() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error('Supabase server secret is not configured');
  return createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });
}
function makeCode() {
  return crypto.randomBytes(9).toString('base64url').replace(/[-_]/g, '').slice(0, 12).toUpperCase();
}
function hashCode(code) {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.scryptSync(code, salt, 64).toString('hex');
  return `${salt}:${hash}`;
}

module.exports = async (req, res) => {
  if (!isAdmin(req)) return res.status(401).json({ error: 'Unauthorized' });
  try {
    const supabase = db();
    if (req.method === 'GET') {
      const q = String(req.query?.q || '').trim();
      let query = supabase.from('student_profiles').select('id,admission_no,roll_no,class_level,stream,academic_session,full_name,father_name,phone,email,registration_no,status,portal_enabled,created_at').order('class_level').order('roll_no');
      if (q) query = query.or(`admission_no.ilike.%${q}%,full_name.ilike.%${q}%,roll_no.ilike.%${q}%`);
      const { data, error } = await query.limit(200);
      if (error) throw error;
      return res.status(200).json({ students: data || [] });
    }
    if (req.method === 'POST') {
      const b = req.body || {};
      const required = ['admission_no','class_level','academic_session','full_name'];
      if (required.some(k => !String(b[k] || '').trim())) return res.status(400).json({ error: 'Required student fields are missing' });
      if (!['9','10','11','12'].includes(String(b.class_level))) return res.status(400).json({ error: 'Invalid class' });
      const code = makeCode();
      const { data: student, error: e1 } = await supabase.from('student_profiles').insert({
        admission_no: String(b.admission_no).trim(), roll_no: String(b.roll_no || '').trim() || null,
        class_level: String(b.class_level), stream: String(b.stream || '').trim() || null,
        academic_session: String(b.academic_session).trim(), full_name: String(b.full_name).trim(),
        father_name: String(b.father_name || '').trim() || null, mother_name: String(b.mother_name || '').trim() || null,
        date_of_birth: b.date_of_birth || null, gender: String(b.gender || '').trim() || null,
        phone: String(b.phone || '').trim() || null, email: String(b.email || '').trim() || null,
        address: String(b.address || '').trim() || null, registration_no: String(b.registration_no || '').trim() || null,
        bseb_roll_code: String(b.bseb_roll_code || '').trim() || null, bseb_roll_no: String(b.bseb_roll_no || '').trim() || null,
        portal_enabled: false
      }).select('id,admission_no,roll_no,class_level,academic_session,full_name').single();
      if (e1) throw e1;
      const { error: e2 } = await supabase.from('student_access_codes').insert({ student_id: student.id, code_hash: hashCode(code) });
      if (e2) throw e2;
      return res.status(201).json({ student, access_code: code, message: 'Save this code securely and give it only to the verified student.' });
    }
    return res.status(405).json({ error: 'Method not allowed' });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Student operation failed' });
  }
};
