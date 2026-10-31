// Sends the contact form through Web3Forms (https://web3forms.com), which e-mails it to the
// site owner, so no e-mail address appears on this website. The access key below is meant to be
// public: it only lets this form deliver messages to the owner's inbox.
const ACCESS_KEY = 'REPLACE_WITH_WEB3FORMS_ACCESS_KEY';
const ENDPOINT = 'https://api.web3forms.com/submit';

const form = document.getElementById('contact-form');
const button = document.getElementById('send-button');
const result = document.getElementById('form-result');
const openedAt = Date.now();

function show(message, isError) {
  result.textContent = message;
  result.className = isError ? 'form-result error' : 'form-result success';
}

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  result.textContent = '';

  const data = new FormData(form);
  const email = String(data.get('email') || '').trim();
  const message = String(data.get('message') || '').trim();

  if (!email || !form.email.checkValidity()) {
    show('Please enter a valid e-mail address so I can reply.', true);
    return;
  }
  if (!message) {
    show('Please write a message.', true);
    return;
  }

  // A filled-in hidden field or a form sent within two seconds is a bot; pretend it worked.
  if (data.get('website') || Date.now() - openedAt < 2000) {
    show('Thank you! Your message was sent.', false);
    form.reset();
    return;
  }

  if (ACCESS_KEY.startsWith('REPLACE')) {
    show('The contact form is not switched on yet. Please try again later.', true);
    return;
  }

  button.disabled = true;
  button.textContent = 'Sending…';
  try {
    const response = await fetch(ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({
        access_key: ACCESS_KEY,
        subject: `Doc Scanner: ${data.get('topic')}`,
        from_name: 'Doc Scanner contact form',
        topic: data.get('topic'),
        name: String(data.get('name') || '').trim() || '(not given)',
        email,
        message
      })
    });
    const body = await response.json();
    if (response.ok && body.success) {
      show('Thank you! Your message was sent. I will answer by e-mail.', false);
      form.reset();
    } else {
      show('Sorry, the message could not be sent. Please try again in a little while.', true);
    }
  } catch (error) {
    show('Sorry, the message could not be sent. Please check your connection and try again.', true);
  } finally {
    button.disabled = false;
    button.textContent = 'Send message';
  }
});
