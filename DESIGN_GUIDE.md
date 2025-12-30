# 🎨 Design Guide - Car Rental Authentication System

## Color Palette

### Primary Colors

```
Primary Blue
HEX: #2563EB
RGB: 37, 99, 235
Usage: Buttons, links, icons, highlights

Primary Blue (Light)
HEX: #3B82F6
RGB: 59, 130, 246
Usage: Hover states, accents

Primary Blue (Dark)
HEX: #1E40AF
RGB: 30, 64, 175
Usage: Active states, emphasis
```

### Neutral Colors

```
Background
HEX: #FFFFFF
RGB: 255, 255, 255

Input Background
HEX: #FAFAFA
RGB: 250, 250, 250

Border
HEX: #E5E7EB
RGB: 229, 231, 235

Text Primary
HEX: #111827
RGB: 17, 24, 39

Text Secondary
HEX: #6B7280
RGB: 107, 114, 128
```

### Semantic Colors

```
Success Green
HEX: #10B981
RGB: 16, 185, 129
Usage: Success messages, confirmations

Error Red
HEX: #EF4444
RGB: 239, 68, 68
Usage: Error messages, validation errors

Warning Orange
HEX: #F59E0B
RGB: 245, 158, 11
Usage: Warning messages

Info Blue
HEX: #3B82F6
RGB: 59, 130, 246
Usage: Information boxes
```

## Typography

### Font Family
**Inter** - Clean, modern, highly readable sans-serif font

### Font Sizes

```
Heading 1 (Page Title)
Size: 28px / 1.75rem
Weight: Bold (700)
Usage: Main page titles

Heading 2 (Section Title)
Size: 24px / 1.5rem
Weight: Bold (700)
Usage: Section headers

Body Large
Size: 16px / 1rem
Weight: Regular (400)
Usage: Button text, important labels

Body Regular
Size: 14px / 0.875rem
Weight: Regular (400)
Usage: Input fields, body text

Body Small
Size: 13px / 0.8125rem
Weight: Regular (400)
Usage: Helper text, captions

Caption
Size: 12px / 0.75rem
Weight: Regular (400)
Usage: Footnotes, timestamps
```

## UI Components

### Text Input Fields

```
Style:
- Border Radius: 12px
- Padding: 16px (vertical), 20px (horizontal)
- Background: #FAFAFA
- Border: 1px solid #E5E7EB
- Height: 56px

States:
- Default: Border #E5E7EB
- Focus: Border #2563EB (2px)
- Error: Border #EF4444
- Disabled: Background #F3F4F6, Text #9CA3AF

Icons:
- Prefix Icon: Left side, 24x24px
- Suffix Icon: Right side, 24x24px (e.g., password toggle)
```

### Buttons

#### Primary Button (Elevated)
```
Style:
- Background: #2563EB
- Foreground: #FFFFFF
- Border Radius: 12px
- Padding: 16px (vertical)
- Font: 16px, Weight 600
- Elevation: 0 (flat)

States:
- Default: Background #2563EB
- Hover: Background #1E40AF
- Pressed: Background #1E3A8A
- Disabled: Background #E5E7EB, Text #9CA3AF
- Loading: Shows CircularProgressIndicator
```

#### Secondary Button (Outlined)
```
Style:
- Background: Transparent
- Border: 1px solid #E5E7EB
- Foreground: #111827
- Border Radius: 12px
- Padding: 16px (vertical)
- Font: 16px, Weight 600

States:
- Default: Border #E5E7EB
- Hover: Background #F9FAFB
- Pressed: Background #F3F4F6
```

#### Text Button
```
Style:
- Background: Transparent
- Foreground: #2563EB
- Font: 14px, Weight 600
- No padding/border

States:
- Default: Text #2563EB
- Hover: Text #1E40AF
- Pressed: Text #1E3A8A
```

### Icons

```
Size: 24x24px (standard)
Size: 80x80px (page headers)
Color: #2563EB (primary)
Style: Outlined (material icons)

Common Icons:
- email_outlined
- lock_outlined
- person_outlined
- phone_outlined
- visibility_outlined / visibility_off_outlined
- directions_car_rounded
- check_circle
```

### Spacing System

```
4px   = 0.25rem (xs)
8px   = 0.5rem  (sm)
12px  = 0.75rem (md)
16px  = 1rem    (lg)
24px  = 1.5rem  (xl)
32px  = 2rem    (2xl)
40px  = 2.5rem  (3xl)
48px  = 3rem    (4xl)
```

### Layout

#### Page Padding
```
All Pages: 24px horizontal padding
Safe Area: Applied to prevent notch overlap
```

#### Form Spacing
```
Between Fields: 16px
After Button: 24px
Section Spacing: 32px
```

#### Card/Container
```
Border Radius: 12px
Padding: 16px
Background: #FFFFFF
Shadow: Optional subtle elevation
```

## Screen Layouts

### Login Page

```
┌─────────────────────────────────────┐
│                                     │ ← 24px padding
│              [Icon]                 │
│           80x80px #2563EB           │
│                                     │
│        Car Rental System            │ ← 28px, Bold
│    Welcome back! Please login       │ ← 14px, Gray
│                                     │
│          [Email Field]              │ ← 16px spacing
│         [Password Field]            │
│                                     │
│    Forgot Password? →               │ ← Text button
│                                     │
│         [Login Button]              │ ← Primary, full width
│                                     │
│         ──── OR ────                │ ← Divider with text
│                                     │
│    [Google Sign-In Button]          │ ← Outlined, full width
│                                     │
│   Don't have an account? Sign Up    │
│                                     │
└─────────────────────────────────────┘
```

### Register Page

```
┌─────────────────────────────────────┐
│  ← Create Account               [✓] │ ← AppBar
├─────────────────────────────────────┤
│              [Icon]                 │ ← Scrollable
│           60x60px #2563EB           │   content
│                                     │
│         Join Us Today               │
│   Create an account to start        │
│                                     │
│        [Full Name Field]            │
│         [Email Field]               │
│         [Phone Field]               │
│         [IC Number Field]           │
│        [Gender Dropdown]            │
│        [Password Field]             │
│     [Confirm Password Field]        │
│                                     │
│   ☑ I agree to Terms                │
│                                     │
│      [Create Account Button]        │
│                                     │
│         ──── OR ────                │
│                                     │
│    [Google Sign-In Button]          │
│                                     │
│   Already have an account? Login    │
│                                     │
└─────────────────────────────────────┘
```

### Reset Password Page

```
┌─────────────────────────────────────┐
│  ← Reset Password                   │ ← AppBar
├─────────────────────────────────────┤
│                                     │
│              [Icon]                 │
│           80x80px #2563EB           │
│                                     │
│        Forgot Password?             │
│   Enter your email address and      │
│   we'll send you a link...          │
│                                     │
│         [Email Field]               │
│                                     │
│      [Send Reset Link Button]       │
│                                     │
│   ┌───────────────────────────┐    │
│   │ ℹ️  Didn't receive email?  │    │ ← Info box
│   │    Check spam folder...    │    │
│   └───────────────────────────┘    │
│                                     │
│   Remember password? Login          │
│                                     │
└─────────────────────────────────────┘
```

## Animations & Transitions

### Page Transitions
```
Type: Material Page Route
Duration: 300ms
Curve: easeInOut
```

### Loading States
```
Type: CircularProgressIndicator
Size: 20x20px
Color: #FFFFFF (on primary buttons)
Stroke Width: 2px
```

### Form Validation
```
Error Text:
- Color: #EF4444
- Size: 13px
- Appears: Instantly
- Position: Below field
```

## Accessibility

### Touch Targets
```
Minimum: 48x48px
Buttons: 56px height
Icon Buttons: 48x48px
```

### Contrast Ratios
```
Text on White: 7:1 (AAA)
Text on Primary Blue: 4.5:1 (AA)
Error Text: 7:1 (AAA)
```

### Focus States
```
All interactive elements have visible focus indicators
Keyboard navigation fully supported
Screen reader compatible labels
```

## Best Practices

### ✅ Do's
- Use consistent spacing throughout
- Follow Material Design 3 guidelines
- Maintain color consistency
- Provide clear error messages
- Show loading states for async operations
- Use icons to enhance understanding
- Test on multiple screen sizes

### ❌ Don'ts
- Don't mix different UI styles
- Don't use colors outside the palette
- Don't create custom input styles
- Don't skip loading indicators
- Don't use tiny touch targets
- Don't overcomplicate layouts
- Don't ignore accessibility

## Responsive Design

### Breakpoints
```
Small Phone: < 360px
Phone: 360px - 600px
Tablet: 600px - 900px
Desktop: > 900px
```

### Adaptations
```
Phone: Single column, full width buttons
Tablet: Same as phone (portrait), Centered form (landscape)
Desktop: Centered form with max-width 400px
```

## Dark Mode (Future Enhancement)

Currently, the app uses light mode only. To add dark mode:

```dart
// Dark Color Palette
Primary: #3B82F6
Background: #111827
Surface: #1F2937
Text Primary: #F9FAFB
Text Secondary: #9CA3AF
Border: #374151
```

## Figma Design System

To create a Figma design system:

1. **Create color styles** for all colors above
2. **Create text styles** for typography
3. **Create components** for buttons, inputs
4. **Create layouts** for each screen
5. **Export assets** at 1x, 2x, 3x for Flutter

## Implementation Notes

### Material 3 Theme
```dart
ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Color(0xFF2563EB),
  ),
  textTheme: GoogleFonts.interTextTheme(),
  // ... other theme properties
)
```

### Custom Colors
```dart
// Use these for custom components
static const primaryBlue = Color(0xFF2563EB);
static const successGreen = Color(0xFF10B981);
static const errorRed = Color(0xFFEF4444);
```

## Assets Needed

While this implementation doesn't require image assets, you may want to add:

- App logo (SVG or PNG)
- Car illustrations
- Empty state illustrations
- Success/error illustrations

Place assets in:
```
assets/
├── images/
│   ├── logo.svg
│   └── car_illustration.svg
└── icons/
    └── custom_icons.svg
```

Don't forget to update `pubspec.yaml`:
```yaml
flutter:
  assets:
    - assets/images/
    - assets/icons/
```

---

**Design System Version:** 1.0  
**Last Updated:** 2025  
**Based on:** Material Design 3

For implementation questions, refer to [AUTH_README.md](AUTH_README.md)
