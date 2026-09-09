const crypto = require('crypto');
const { createClient } = require('@supabase/supabase-js');

function db() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error('Supabase server secret is not configured');
  return createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });
}
function verifyCode(code, stored) {
  const [salt, expected] = String(stored || '').split(':');
  if (!salt || !expected) return false;
  const actual = crypto.scryptSync(String(code || ''), salt, 64).toString('hex');
  const a = Buffer.from(actual, 'hex');
  const b = Buffer.from(expected, 'hex');
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  const auth = String(req.headers.authorization || '');
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!token) return res.status(401).json({ error: 'Login required' });
  try {
    const supabase = db();
    const { data: authData, error: authError } = await supabase.auth.getUser(token);
    if (authError || !authData?.user) return res.status(401).json({ error: 'Invalid login session' });
    const { admission_no, access_code } = req.body || {};
    if (!admission_no || !access_code) return res.status(400).json({ error: 'Admission number and access code are required' });

    const { data: student, error: e1 } = await supabase.from('student_profiles').select('*').eq('admission_no', String(admission_no).trim()).maybeSingle();
    if (e1 || !student) return res.status(404).json({ error: 'Student record not found' });
    if (student.auth_user_id && student.auth_user_id !== authData.user.id) return res.status(409).json({ error: 'This student record is already linked to another account' });
    if (student.status !== 'active') return res.status(403).json({ error: 'Student portal access is disabled' });

    const { data: access, error: e2 } = await supabase.from('student_access_codes').select('*').eq('student_id', student.id).maybeSingle();
    if (e2 || !access || access.used_at || (access.expires_at && new Date(access.expires_at) < new Date())) return res.status(403).json({ error: 'Access code is invalid or expired' });
    if (!verifyCode(access_code, access.code_hash)) return res.status(403).json({ error: 'Access code is invalid' });

    const patch = { auth_user_id: authData.user.id, portal_enabled: true, updated_at: new Date().toISOString() };
    if (authData.user.email) patch.email = authData.user.email;
    if (authData.user.phone) patch.phone = authData.user.phone;
    const { data: updated, error: e3 } = await supabase.from('student_profiles').update(patch).eq('id', student.id).select('id,admission_no,roll_no,class_level,stream,academic_session,full_name,father_name,mother_name,date_of_birth,gender,phone,email,registration_no,bseb_roll_code,bseb_roll_no,portal_enabled,status').single();
    if (e3) throw e3;
    await supabase.from('student_access_codes').update({ used_at: new Date().toISOString() }).eq('id', access.id);
    return res.status(200).json({ student: updated });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Account claim failed' });
  }
};
