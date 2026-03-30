const API_BASE_URL = 'http://localhost:5000';

// Registration Function
async function registerAccount(formData) {
  try {
    const response = await fetch(`${API_BASE_URL}/api/accounts/register`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(formData)
    });

    const data = await response.json();

    if (data.success) {
      alert('Account created successfully!');
      const form = document.getElementById('registerForm');
      if (form) form.reset();
    } else {
      alert('Error: ' + data.message);
    }
  } catch (error) {
    console.error('Error:', error);
    alert('Connection error. Make sure the server is running on port 5000.');
  }
}

// Login Function
async function loginAccount(formData) {
  try {
    const response = await fetch(`${API_BASE_URL}/api/accounts/login`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(formData)
    });

    const data = await response.json();

    if (data.success) {
      localStorage.setItem('user', JSON.stringify(data.account));
      window.location.href = 'pages/dashboard.html';
    } else {
      alert('Error: ' + data.message);
    }
  } catch (error) {
    console.error('Error:', error);
    alert('Connection error. Make sure the server is running on port 5000.');
  }
}

// Get Current User from localStorage
function getCurrentUser() {
  const user = localStorage.getItem('user');
  return user ? JSON.parse(user) : null;
}

// Logout - Clear localStorage and redirect
function logoutUser() {
  localStorage.removeItem('user');
  window.location.href = 'index.html';
}
