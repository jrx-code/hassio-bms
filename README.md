# Vault-Tec BMS Automation (v1.2.0)

![Vault-Tec System](https://github.com/jrx-code/hassio-bms/blob/main/images/image.png?raw=true)

> *"Prepared for the Future."*

**Vault-Tec BMS** is an advanced, heuristic-based energy management system designed for Home Assistant and FoxESS inverters. Unlike standard schedulers, this system calculates the **exact minute** charging must start to achieve the target State of Charge (SoC) precisely when the tariff window ends.

---

## ⚙️ System Overview

This system replaces dumb timers with intelligent, environmental-aware logic. It creates a bridge between your solar forecast, weather conditions, and battery physics.

### Core Assumptions
1.  **Just-in-Time Charging:** The battery should finish charging exactly at the end of the cheap tariff window (06:00 or 15:00). Sitting at 100% SoC for hours is inefficient and harmful to cells.
2.  **Solar First:** If the forecast predicts enough sun to cover demand, grid charging is reduced or cancelled.
3.  **Environmental Awareness:** Cold batteries charge slower. Heat pumps consume more power in winter. The system adjusts math based on temperature and season.
4.  **Race Condition Safety:** The system is immune to "Unavailable/Unknown" states during Home Assistant restarts.

---

## 🔌 System Input Requirements

To function correctly, the **RobCo Logic Engine** (`bms.jinja`) requires specific telemetry data. Ensure your sensors match the types and values below.

### Critical Entities Map

| Entity (Variable Name) | Expected Type / Unit | Required Values / Format | Description |
| :--- | :--- | :--- | :--- |
| `sensor.battery_soc_raw` | **Integer** `(%)` | `0` - `100` | Real-time SoC directly from BMS/Modbus. Must be instant. |
| `sensor.solcast_pv_forecast...` | **Float** `(kWh)` | `>= 0.0` | **Remaining** energy forecast for today. Defines solar offset. |
| `sensor.openweathermap_temperature` | **Float** `(°C)` | Any (`-30` to `50`) | Ambient temp. Drives charging efficiency & heat pump demand logic. |
| `sensor.pora_roku` | **String** | `'zima'`, `'wiosna'`, `'lato'`, `'jesień'` | Season sensor. **Must be in Polish** to match Jinja logic map. |
| `sensor.openweathermap_condition` | **String** | `cloudy`, `rainy`, `sunny`, etc. | Weather condition. Used to lower solar confidence in bad weather. |
| `select.work_mode` | **Select** | `Self Use`, `Force Charge` | The control entity for the FoxESS Inverter. |

> **Note:** If your season sensor returns English values (e.g., 'winter'), you must edit `config/custom_templates/bms.jinja` to match them.

---

## 🧠 How It Works (The Logic Loop)

The brain of the operation resides in `bms.jinja`. Every minute, the system performs the following calculations:

### 1. The Heuristic Calculation
The system calculates the **Energy Deficit**:
$$ \text{Needed kWh} = \min(\text{Predicted Demand}, \text{Capacity}) - \text{Current Energy} $$

Then, it applies **Dynamic Modifiers**:
* **Season Factor:** Adjusts demand prediction based on time of year (e.g., Winter = 1.8x demand).
* **Weather Factor:** Reduces solar confidence during rain/snow.
* **Temp Factor:** Adjusts efficiency assumptions based on ambient temperature.

### 2. Execution (The Trigger)
Finally, it solves for $T_{start}$:
$$ T_{start} = T_{target} - \left( \frac{\text{Grid Needed (kWh)}}{\text{Charge Power (kW)}} \times 1.1 \right) $$
*(1.1 is a 10% efficiency buffer)*

When `now() >= calculated_start_time`, the Automation triggers:
1.  **Switch Inverter Mode:** Sets FoxESS to `Force Charge`.
2.  **Notify Overseer:** Sends a Mobile App notification with current SoC.

---

## 📂 Project Structure

| File | Description |
| :--- | :--- |
| **`config/custom_templates/bms.jinja`** | **The Brain.** Contains the heavy mathematical macros and logic modifiers. |
| **`config/packages/bms/1_infrastructure.yaml`** | **The Hardware.** Input Booleans (Safety Switch) and Modbus Proxy sensors. |
| **`config/packages/bms/2_logic.yaml`** | **The Sensors.** Template sensors that expose the calculated start times to HA. |
| **`config/automations/automation_reference.yaml`** | **The Enforcer.** Automation triggers & actions to paste into the HA UI. |
| **`cards/`** | Lovelace card YAML for battery / debug dashboards. |

---

## 🚀 Installation

1.  **Copy Files:** Copy `config/packages` and `config/custom_templates` from this repo into your Home Assistant `/config/` directory (so you get `/config/packages/...` and `/config/custom_templates/...`).
2.  **Update Config:** Ensure your `configuration.yaml` allows packages:
    ```yaml
    homeassistant:
      packages: !include_dir_named packages
    ```
3.  **Restart:** Reboot Home Assistant Core.
4.  **Create Automation:** Copy the code from `config/automations/automation_reference.yaml` and paste it into a new Automation (Edit in YAML mode).
5.  **Dashboard image (optional):** The repo already ships `images/image.png` for the README; Lovelace card YAML under `cards/` references entities you configure locally.

---

## 🛡️ Safety Protocols

* **Master Switch:** An `input_boolean.bms_automation` acts as a Kill Switch. If OFF, no actions are taken.
* **Hysteresis:** Charging will not trigger if SoC is already > 95%.
* **Startup Protection:** Logic includes `is not none` checks to prevent false triggers during HA boot-up.

---

*Property of RobCo Industries. Unauthorized access is a Class A felony.*
