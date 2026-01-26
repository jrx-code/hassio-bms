# ☢️ Vault-Tec Battery Interface

![Vault-Tec Interface](https://github.com/jrx-code/hassio-bms/blob/main/images/card-image.png?raw=true)

> *"Efficiency is the key to survival."*

This directory contains the custom **Pip-Boy 3000** styled interface card for the Vault-Tec BMS. It is designed to visualize the battery state, automation logic, and charging schedules in a retro-futuristic CRT style.

## 📋 File Overview

| File | Description |
| :--- | :--- |
| **`battery-card.yaml`** | The main code for the custom card. Contains all CSS, HTML, and JS logic for the CRT effect and animations. |

---

## 🛠️ Requirements

To render this card correctly, your Home Assistant instance must have the following frontend resources installed (via HACS):

1.  **`button-card`** (Main engine)
    * *Required for:* Advanced templating, JS logic, and custom CSS.
2.  **`card-mod`** (Optional but recommended)
    * *Required for:* Advanced global styling if needed.

---

## 📟 How to Use

There are two ways to add this card to your Lovelace Dashboard:

### Method 1: The Clean Way (Recommended)
If you are using `yaml` mode or want to keep your dashboard clean:

1.  Ensure this file is accessible in your config (e.g., `config/cards/battery-card.yaml`).
2.  Add the following to your dashboard configuration:

```yaml
- type: vertical-stack
  cards:
    - !include cards/battery-card.yaml
```

### Method 2: The UI Way
1.  Open your Dashboard and click **Edit Dashboard**.
2.  Click **Add Card** -> **Manual** (at the very bottom).
3.  Copy the entire content of `battery-card.yaml` and paste it into the code editor.
4.  Click **Save**.

---

## 🎨 Features & Visuals

* **CRT Effect:** Scanlines, vignette, and screen flicker animations generated purely via CSS (no background images required).
* **Transparent Design:** The card uses transparency to blend with your dashboard background while maintaining the green phosphor aesthetic.
* **Dynamic Animations:**
    * **Charging:** The progress bar animates with a "scanning" effect when `select.work_mode` is set to `Force Charge`.
    * **Status Indicators:** Text blinks or changes color based on system state (Safety Lock / Online).
* **Responsive Layout:** Uses CSS Grid to ensure elements (Header, Data, Footer) stay aligned regardless of screen width.

---

*Property of RobCo Industries. Unauthorized modification may void your warranty.*
