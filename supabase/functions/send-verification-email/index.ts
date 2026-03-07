// Supabase Edge Function to send verification emails via MailerSend
// This works server-side, avoiding CORS issues on web

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const MAILERSEND_API_KEY = Deno.env.get('MAILERSEND_API_KEY') || ''
const MAILERSEND_FROM_EMAIL = Deno.env.get('MAILERSEND_FROM_EMAIL') || 'fcarsy0001@gmail.com'
const MAILERSEND_FROM_NAME = Deno.env.get('MAILERSEND_FROM_NAME') || 'Car Rental System'

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      },
    })
  }

  try {
    const { email, otp, token, type } = await req.json()

    if (!email) {
      return new Response(
        JSON.stringify({ error: 'Email is required' }),
        { 
          status: 400, 
          headers: { 
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          } 
        }
      )
    }

    if (!MAILERSEND_API_KEY) {
      return new Response(
        JSON.stringify({ error: 'MailerSend API key not configured' }),
        { 
          status: 500, 
          headers: { 
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          } 
        }
      )
    }

    // Determine email content
    let subject: string
    let htmlBody: string

    if (type === 'otp' && otp) {
      subject = 'Car Rental System - Email Verification Code'
      htmlBody = getOTPEmailBody(otp)
    } else if (type === 'link' && token) {
      subject = 'Car Rental System - Verify Your Email Address'
      htmlBody = getVerificationLinkEmailBody(token)
    } else {
      return new Response(
        JSON.stringify({ error: 'Invalid email type or missing data' }),
        { 
          status: 400, 
          headers: { 
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          } 
        }
      )
    }

    // Call MailerSend API server-side (no CORS issues)
    const mailerSendResponse = await fetch('https://api.mailersend.com/v1/email', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${MAILERSEND_API_KEY}`,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: JSON.stringify({
        from: {
          email: MAILERSEND_FROM_EMAIL,
          name: MAILERSEND_FROM_NAME,
        },
        to: [
          {
            email: email,
          }
        ],
        subject: subject,
        html: htmlBody,
      }),
    })

    const responseData = await mailerSendResponse.json()

    if (mailerSendResponse.status === 202 || mailerSendResponse.status === 200) {
      return new Response(
        JSON.stringify({ 
          success: true,
          message: 'Email sent successfully',
          data: responseData
        }),
        { 
          status: 200,
          headers: { 
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          } 
        }
      )
    } else {
      return new Response(
        JSON.stringify({ 
          success: false,
          error: 'MailerSend API error',
          status: mailerSendResponse.status,
          data: responseData
        }),
        { 
          status: mailerSendResponse.status,
          headers: { 
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          } 
        }
      )
    }
  } catch (error) {
    return new Response(
      JSON.stringify({ 
        error: error.message,
        stack: error.stack 
      }),
      { 
        status: 500, 
        headers: { 
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        } 
      }
    )
  }
})

function getOTPEmailBody(otp: string): string {
  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background-color: #2563EB; color: white; padding: 20px; text-align: center; border-radius: 8px 8px 0 0; }
    .content { background-color: #f9fafb; padding: 30px; border-radius: 0 0 8px 8px; }
    .otp-box { background-color: white; border: 2px solid #2563EB; border-radius: 8px; padding: 20px; text-align: center; margin: 20px 0; }
    .otp-code { font-size: 32px; font-weight: bold; color: #2563EB; letter-spacing: 8px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>Car Rental System</h1>
      <p>Email Verification</p>
    </div>
    <div class="content">
      <h2>Hello,</h2>
      <p>Thank you for registering with Car Rental System. Please use the following OTP code to verify your email address:</p>
      <div class="otp-box">
        <p style="margin: 0; color: #666; font-size: 14px;">Your verification code:</p>
        <div class="otp-code">${otp}</div>
      </div>
      <p>This code will expire in <strong>10 minutes</strong>.</p>
      <p>Best regards,<br>Car Rental System Team</p>
    </div>
  </div>
</body>
</html>
  `
}

function getVerificationLinkEmailBody(token: string): string {
  const verificationUrl = `carrentalsystem://verify?token=${token}`
  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background-color: #2563EB; color: white; padding: 20px; text-align: center; border-radius: 8px 8px 0 0; }
    .content { background-color: #f9fafb; padding: 30px; border-radius: 0 0 8px 8px; }
    .button { display: inline-block; background-color: #2563EB; color: white; padding: 15px 30px; text-decoration: none; border-radius: 8px; margin: 20px 0; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>Car Rental System</h1>
      <p>Email Verification</p>
    </div>
    <div class="content">
      <h2>Hello,</h2>
      <p>Thank you for registering with Car Rental System. Please click the button below to verify your email address:</p>
      <div style="text-align: center;">
        <a href="${verificationUrl}" class="button">Verify Email Address</a>
      </div>
      <p>This link will expire in <strong>24 hours</strong>.</p>
      <p>Best regards,<br>Car Rental System Team</p>
    </div>
  </div>
</body>
</html>
  `
}

