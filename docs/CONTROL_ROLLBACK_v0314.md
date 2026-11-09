# v0.3.14-control-rollback

Artem (GPT), T036/Issue58 + T037/Issue59, reviewer Олег (Kimi). Новый кандидат
после[run9083407516](probes/9083407516/REPORT.md), безmerge.

1. Убран installed personal ROAM entry и delivery_lane_guard flag выключен.
   Root больше не вызывает guard sampling. Шаги/атаки guard не участвуют в новом
   матче; исходник эксперимента сохранён, но не является активной policy.
   Native ROAM возвращается **отсутствием** entry при чистой установке. Обычная
   доставка и прежний personal ITEM baselinev0312 сохраняются. Courierdetours
   могут снова встречаться: исправление отозвано из-за регресса управления.
2. Разделены rawPTstate и heroATTRIBUTE enums. Currentclient:PT STR0/INT1/AGI2.
   Fixture теперь хранит semanticattribute отдельно и возвращает настоящийrawPTcode.
   Старый0313 запрашивал raw1 как«AGI», поэтому SF реально держалINT и терял10damage.
3. AGI по умолчанию дляAA/farm иregen, INT на конкретныйcastintent с readback,
   сохранены anti-spam/timeout иWandcharge rules. Из-за малогоmana самопроизвольного
   постоянногоINT нет: это снова уменьшило бы готовность кlast-hit.
4. Observer дополняется rawPTstate, hero.attack_damage ужечитаетсяизenginefresh.
   +10 вручную не добавлять: это повторныйучёт того жеPTбонуса. NativeAA controller
   остаётсяValve, новыйlast-hitcontroller не вводится.

Проверка: новый матч>=12мин, waveform/strafe безguard, PTraw2 приfarm иполныйdamage,
PTraw1 приspellprepare, Bottle/fountainAGI, Stick/Wand15%/lethalmana/empty.
Ward0/5/10 долженсохраниться. У snapshot item_power_treads сверять treads_raw_state,
hero.attack_damage/maxmana, атаки иrelease; ни один переключатель не обещаетkill.
Рунический повтор6мин переданОлегу (Kimi), PR53unchanged, не смешивать его сguard.

Package contract проверяет, что upgrade поверх старойпапки черезcheckedreplace
действительно удаляет mode_roam_nevermore.lua и сохраняетего вbackup. Falseflag
сам по себе не возвращал быnativeROAM, поэтому установка только полнойзаменой.
