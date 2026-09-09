const SUPABASE_URL = "https://rxbhgqnvcrcgjyacdudf.supabase.co";
const SUPABASE_KEY = "sb_publishable_ZEqI7HjGd3Vp4IpkH7y-uA_-JjYsURu";

const supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
const $ = (id) => document.getElementById(id);

let pendingOtpEmail = "";
let pendingOtpClaim = null;

function showOtpBox(email) {
  pendingOtpEmail = String(email || "").trim().toLowerCase();

  $("loginBox")?.classList.add("hidden");
  $("signupBox")?.classList.add("hidden");
  $("otpBox")?.classList.remove("hidden");

  const input = $("otpCode");
  if (input) {
    input.value = "";
    setTimeout(() => input.focus(), 50);
  }

  setMessage(
    "otpMessage",
    `हमने ${pendingOtpEmail} पर 6-digit OTP भेजा है।`,
    true
  );
}

function hideOtpBox() {
  $("otpBox")?.classList.add("hidden");
  $("signupBox")?.classList.remove("hidden");
  $("signupTab")?.classList.add("active");
  $("loginTab")?.classList.remove("active");
  setMessage("otpMessage", "");
}

async function sendStudentOtp(email) {
  const { error } = await supabaseClient.auth.signInWithOtp({
    email,
    options: {
      shouldCreateUser: false
    }
  });

  return error || null;
}

async function verifyStudentOtp(event) {
  event?.preventDefault();

  const email = pendingOtpEmail;
  const token = $("otpCode")?.value.trim() || "";

  if (!email) {
    setMessage("otpMessage", "OTP session नहीं मिली। फिर से Signup करें।");
    return false;
  }

  if (!/^\d{6}$/.test(token)) {
    setMessage("otpMessage", "कृपया 6-digit OTP दर्ज करें।");
    return false;
  }

  setBusy("verifyOtpButton", true, "Verifying…", "Verify OTP");
  setMessage("otpMessage", "OTP verify हो रहा है…", true);

  const { data, error } = await supabaseClient.auth.verifyOtp({
    email,
    token,
    type: "email"
  });

  if (error) {
    setBusy("verifyOtpButton", false, "", "Verify OTP");
    setMessage("otpMessage", friendlyAuthError(error));
    return false;
  }

  if (!data?.session) {
    setBusy("verifyOtpButton", false, "", "Verify OTP");
    setMessage(
      "otpMessage",
      "OTP verify हुआ, लेकिन login session नहीं मिला। फिर से Login करें।"
    );
    return false;
  }

  if (pendingOtpClaim) {
    localStorage.setItem(
      "pending_student_claim",
      JSON.stringify(pendingOtpClaim)
    );
  }

  const claimed = await claimStudent("otpMessage");

  setBusy("verifyOtpButton", false, "", "Verify OTP");

  if (!claimed) return false;

  pendingOtpEmail = "";
  pendingOtpClaim = null;
  return false;
}

async function resendStudentOtp() {
  const email = pendingOtpEmail;

  if (!email) {
    setMessage("otpMessage", "OTP session नहीं मिली। फिर से Signup करें।");
    return false;
  }

  setBusy("resendOtpButton", true, "Sending…", "Resend OTP");
  setMessage("otpMessage", "नया OTP भेजा जा रहा है…", true);

  const error = await sendStudentOtp(email);

  setBusy("resendOtpButton", false, "", "Resend OTP");

  if (error) {
    setMessage("otpMessage", friendlyAuthError(error));
    return false;
  }

  const input = $("otpCode");
  if (input) input.value = "";

  setMessage(
    "otpMessage",
    "नया 6-digit OTP आपके email पर भेज दिया गया है।",
    true
  );

  return true;
}


function setMessage(id, text, success = false) {
  const el = $(id);
  if (!el) return;
  el.textContent = text || "";
  el.classList.toggle("show", Boolean(text));
  el.classList.toggle("success", success);
}

function setBusy(id, busy, busyText, normalText) {
  const button = $(id);
  if (!button) return;
  button.disabled = busy;
  button.textContent = busy ? busyText : normalText;
}

function showLogin() {
  $("loginBox")?.classList.remove("hidden");
  $("signupBox")?.classList.add("hidden");
  $("loginTab")?.classList.add("active");
  $("signupTab")?.classList.remove("active");
  setMessage("signupMessage", "");
}

function showSignup() {
  $("loginBox")?.classList.add("hidden");
  $("signupBox")?.classList.remove("hidden");
  $("signupTab")?.classList.add("active");
  $("loginTab")?.classList.remove("active");
  setMessage("loginMessage", "");
}

function showDashboard() {
  $("authSection")?.classList.add("hidden");
  $("dashboardSection")?.classList.add("visible");
  $("logoutBtn")?.classList.add("visible");
}

function hideDashboard() {
  $("authSection")?.classList.remove("hidden");
  $("dashboardSection")?.classList.remove("visible");
  $("logoutBtn")?.classList.remove("visible");
}

function setText(id, value) {
  const el = $(id);
  if (!el) return;
  el.textContent = value !== undefined && value !== null && String(value).trim() !== "" ? value : "—";
}

function renderStudent(profile, user) {
  const name = profile?.full_name || user?.user_metadata?.full_name || "Student";
  const classLevel = profile?.class_level || "Class";

  setText("studentName", name);
  setText("studentClass", classLevel);
  setText("admissionNo", profile?.admission_no);
  setText("rollNo", profile?.roll_no);
  setText("classLevel", profile?.class_level);
  setText("session", profile?.academic_session);
  setText("fatherName", profile?.father_name);
  setText("motherName", profile?.mother_name);
  setText("dob", profile?.date_of_birth);
  setText("gender", profile?.gender);
  setText("phone", profile?.phone);
  setText("email", profile?.email || user?.email);
  setText("registrationNo", profile?.registration_no);
  setText("bsebRollNo", profile?.bseb_roll_no);
}

async function signup(event) {
  event?.preventDefault();

  const name = $("signupName")?.value.trim();
  const email = $("signupEmail")?.value.trim().toLowerCase();
  const password = $("signupPassword")?.value || "";
  const admission = $("signupAdmission")?.value.trim();
  const code = $("signupCode")?.value.trim();

  if (!name || !email || !password || !admission || !code) {
    setMessage("signupMessage", "सभी जानकारी भरना जरूरी है।");
    return false;
  }

  if (password.length < 6) {
    setMessage("signupMessage", "Password कम से कम 6 characters का होना चाहिए।");
    return false;
  }

  setBusy(
    "signupButton",
    true,
    "Account बनाया जा रहा है…",
    "Create Student Account"
  );
  setMessage("signupMessage", "Account बनाया जा रहा है…", true);

  const { data, error } = await supabaseClient.auth.signUp({
    email,
    password,
    options: {
      data: {
        full_name: name
      }
    }
  });

  if (error) {
    setBusy("signupButton", false, "", "Create Student Account");
    setMessage("signupMessage", friendlyAuthError(error));
    return false;
  }

  pendingOtpEmail = email;
  pendingOtpClaim = {
    admission_no: admission,
    access_code: code
  };

  localStorage.setItem(
    "pending_student_claim",
    JSON.stringify(pendingOtpClaim)
  );

  if (data?.session) {
    await claimStudent("signupMessage");
    setBusy("signupButton", false, "", "Create Student Account");
    return false;
  }

  showOtpBox(email);

  setBusy("signupButton", false, "", "Create Student Account");
  return false;
}

async function login(event) {
  event?.preventDefault();

  const email = $("loginEmail")?.value.trim().toLowerCase();
  const password = $("loginPassword")?.value || "";

  if (!email || !password) {
    setMessage("loginMessage", "Email और Password भरें।");
    return false;
  }

  setBusy("loginButton", true, "Signing in…", "Login securely");
  setMessage("loginMessage", "Login हो रहा है…", true);

  const { data, error } = await supabaseClient.auth.signInWithPassword({
    email,
    password
  });

  if (error) {
    const lower = String(error.message || "").toLowerCase();

    if (lower.includes("email not confirmed")) {
      pendingOtpEmail = email;
      pendingOtpClaim = null;

      const resendError = await sendStudentOtp(email);

      if (resendError) {
        setBusy("loginButton", false, "", "Login securely");
        setMessage("loginMessage", friendlyAuthError(resendError));
        return false;
      }

      showOtpBox(email);
      setMessage(
        "otpMessage",
        "Email अभी verify नहीं है। नया 6-digit OTP भेज दिया गया है।",
        true
      );

      setBusy("loginButton", false, "", "Login securely");
      return false;
    }

    setBusy("loginButton", false, "", "Login securely");
    setMessage("loginMessage", friendlyAuthError(error));
    return false;
  }

  if (localStorage.getItem("pending_student_claim")) {
    await claimStudent("loginMessage");
  } else {
    await loadStudent();
  }

  setBusy("loginButton", false, "", "Login securely");
  return false;
}

async function claimStudent(messageId = "signupMessage") {
  const { data } = await supabaseClient.auth.getSession();
  const token = data?.session?.access_token;
  const pendingRaw = localStorage.getItem("pending_student_claim");

  if (!token) {
    setMessage(messageId, "Login session नहीं मिला। फिर से Login करें।");
    return false;
  }
  if (!pendingRaw) {
    await loadStudent();
    return true;
  }

  let claim;
  try {
    claim = JSON.parse(pendingRaw);
  } catch {
    localStorage.removeItem("pending_student_claim");
    setMessage(messageId, "Signup information invalid है। फिर से Signup करें।");
    return false;
  }

  try {
    const response = await fetch("/api/student/claim", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer " + token
      },
      body: JSON.stringify(claim)
    });

    const result = await response.json().catch(() => ({}));

    if (!response.ok) {
      setMessage(messageId, result.error || "Student record link नहीं हो पाया।");
      return false;
    }

    localStorage.removeItem("pending_student_claim");
    if (result.student) localStorage.setItem("student_profile", JSON.stringify(result.student));
    await loadStudent();
    return true;
  } catch (error) {
    console.error("Student claim error:", error);
    setMessage(messageId, "Student API उपलब्ध नहीं है। Vercel Dev या deployed Vercel URL से test करें।");
    return false;
  }
}

async function loadStudent() {
  const { data, error } = await supabaseClient.auth.getUser();
  if (error || !data?.user) {
    hideDashboard();
    showLogin();
    return false;
  }

  let profile = null;
  try {
    const { data: row, error: profileError } = await supabaseClient
      .from("student_profiles")
      .select("id,admission_no,roll_no,class_level,stream,academic_session,full_name,father_name,mother_name,date_of_birth,gender,phone,email,registration_no,bseb_roll_code,bseb_roll_no,portal_enabled,status")
      .eq("auth_user_id", data.user.id)
      .eq("portal_enabled", true)
      .maybeSingle();

    if (!profileError) profile = row;
  } catch (e) {
    console.warn("Profile read failed:", e);
  }

  if (!profile) {
    try {
      profile = JSON.parse(localStorage.getItem("student_profile") || "null");
    } catch {
      profile = null;
    }
  }

  renderStudent(profile, data.user);
  if (profile) localStorage.setItem("student_profile", JSON.stringify(profile));
  showDashboard();
  return true;
}

async function refreshStudent() {
  const ok = await loadStudent();
  if (!ok) return;
  const button = document.querySelector(".refresh");
  if (button) {
    const old = button.textContent;
    button.textContent = "✓ Updated";
    setTimeout(() => { button.textContent = old; }, 1400);
  }
}

async function logout() {
  await supabaseClient.auth.signOut();
  localStorage.removeItem("student_profile");
  localStorage.removeItem("pending_student_claim");
  hideDashboard();
  showLogin();
}

function friendlyAuthError(error) {
  const message = String(error?.message || "");
  const lower = message.toLowerCase();
  if (lower.includes("invalid login credentials")) return "Email या Password गलत है।";
  if (lower.includes("email not confirmed")) return "पहले अपने email की confirmation करें, फिर Login करें।";
  if (lower.includes("user already registered")) return "यह email पहले से registered है। Login करें।";
  if (lower.includes("password should be at least")) return "Password कम से कम 6 characters का होना चाहिए।";
  return message || "Authentication में समस्या हुई। फिर से प्रयास करें।";
}

document.querySelectorAll(".toggle-password").forEach((button) => {
  button.addEventListener("click", () => {
    const input = $(button.dataset.target);
    if (!input) return;
    const visible = input.type === "text";
    input.type = visible ? "password" : "text";
    button.textContent = visible ? "Show" : "Hide";
  });
});


document.getElementById("otpForm")?.addEventListener(
  "submit",
  verifyStudentOtp
);

document.getElementById("resendOtpButton")?.addEventListener(
  "click",
  resendStudentOtp
);

document.getElementById("backToSignupButton")?.addEventListener(
  "click",
  () => {
    pendingOtpEmail = "";
    pendingOtpClaim = null;
    hideOtpBox();
  }
);

document.getElementById("otpCode")?.addEventListener(
  "input",
  (event) => {
    event.target.value = event.target.value
      .replace(/\D/g, "")
      .slice(0, 6);
  }
);

document.addEventListener("DOMContentLoaded", async () => {
  const { data } = await supabaseClient.auth.getSession();
  if (data?.session) await loadStudent();
  else {
    hideDashboard();
    showLogin();
  }
});

supabaseClient.auth.onAuthStateChange((event) => {
  if (event === "SIGNED_OUT") {
    hideDashboard();
    showLogin();
  }
});
