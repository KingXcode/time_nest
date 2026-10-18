import 'package:flutter/material.dart';

import 'dashboard_client.dart';
import 'dashboard_widgets.dart';
import 'holiday_logic.dart';

const _teal = Color(0xFF67D8C2);
const _muted = Color(0xFF9BA8AF);

class HolidayPanel extends StatefulWidget {
  const HolidayPanel({
    super.key,
    required this.client,
    required this.leaveDays,
    required this.onLeaveDaysChanged,
    this.now,
  });
  final DashboardClient client;
  final int leaveDays;
  final ValueChanged<int> onLeaveDaysChanged;
  final DateTime Function()? now;

  @override
  State<HolidayPanel> createState() => _HolidayPanelState();
}

class _HolidayPanelState extends State<HolidayPanel> {
  late int _year;
  late int _month;
  DateTime get _today => holidayDate((widget.now ?? DateTime.now)());

  @override
  void initState() {
    super.initState();
    _year = _today.year;
    _month = _today.month;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              key: ValueKey('holiday-year-$_year'),
              initialValue: _year,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '年份',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                for (
                  var year = _today.year - 1;
                  year <= _today.year + 2;
                  year++
                )
                  DropdownMenuItem(value: year, child: Text('$year 年')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _year = value);
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<int>(
              key: ValueKey('holiday-month-$_month'),
              initialValue: _month,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '月份',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                for (var month = 1; month <= 12; month++)
                  DropdownMenuItem(value: month, child: Text('$month 月')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _month = value);
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      ApiSection(
        client: widget.client,
        module: 'holidays',
        args: {'year': _year},
        sourceLabel: 'holiday-cn · 国务院公告整理',
        sourceUrl: 'https://github.com/NateScarlet/holiday-cn',
        builder: (context, response) => _content(response.data),
      ),
    ],
  );

  Widget _content(Map<String, dynamic> data) {
    final schedule = HolidaySchedule.fromJson(data, year: _year);
    final plan = schedule.bestPlan(_today, budget: widget.leaveDays);
    final countdown = _today.year == _year ? schedule.nextBreak(_today) : null;
    final papers = (data['papers'] as List? ?? const [])
        .whereType<String>()
        .where((url) => Uri.tryParse(url)?.scheme == 'https')
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!schedule.known)
          const _Notice(
            icon: Icons.event_busy_outlined,
            title: '官方调休安排待公布或暂不可用',
            detail: '仅显示日期，不推算官方假期或拼假方案。可切换年份，或稍后刷新。',
          )
        else if (countdown != null)
          _Notice(
            icon: Icons.weekend_outlined,
            title: countdown.workdays == 0
                ? '正在休息 · 本段还剩 ${countdown.length} 天'
                : '再工作 ${countdown.workdays} 天，就到下一段休息',
            detail:
                '${_range(countdown.start, countdown.end)} · ${countdown.length} 天连续休息，已计入调休补班',
          )
        else
          _Notice(
            icon: Icons.event_available_outlined,
            title: '$_year 年调休日历',
            detail: _year < _today.year
                ? '历史安排供查询，不推荐已过去的拼假方案。'
                : '选择月份查看放假与补班日期。',
          ),
        const SizedBox(height: 16),
        _calendar(schedule, plan),
        const SizedBox(height: 10),
        const Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            _Legend('休', '官方放假', _teal),
            _Legend('班', '调休补班', Color(0xFFECC48D)),
            _Legend('●', '周末休息', _muted),
          ],
        ),
        const SizedBox(height: 20),
        const Text('想请几天假？', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 6,
          children: [
            for (var days = 0; days <= 5; days++)
              ChoiceChip(
                label: Text('$days 天'),
                selected: widget.leaveDays.clamp(0, 5) == days,
                onSelected: (_) => widget.onLeaveDaysChanged(days),
                selectedColor: _teal.withValues(alpha: .18),
                showCheckmark: false,
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (plan != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: .07),
              border: Border.all(color: _teal.withValues(alpha: .22)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '请 ${plan.leaveDays} 天，连休 ${plan.length} 天',
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w600,
                    color: _teal,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  _range(plan.start, plan.end),
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 7),
                Text(
                  plan.leaveDates.isEmpty
                      ? '无需请假，安心安排一个小假期。'
                      : '请假日期：${plan.leaveDates.map(_shortDate).join('、')}',
                  style: const TextStyle(color: _muted, height: 1.5),
                ),
                if (plan.start.month != _month)
                  TextButton.icon(
                    onPressed: () => setState(() => _month = plan.start.month),
                    icon: const Icon(Icons.calendar_month_outlined, size: 17),
                    label: Text('查看 ${plan.start.month} 月日历'),
                  ),
              ],
            ),
          ),
        ] else
          Text(
            schedule.known ? '未来 120 天内，所选年份没有可推荐的连休方案。' : '确认官方安排后，才会计算拼假。',
            style: const TextStyle(color: _muted, height: 1.5),
          ),
        const SizedBox(height: 10),
        if (schedule.known && !schedule.boundaryKnown)
          const Padding(
            padding: EdgeInsets.only(bottom: 7),
            child: Text(
              '下一年的公告尚未完整取得，12 月可能受跨年调休影响，暂不参与连休与倒计时计算。',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFFECC48D),
                height: 1.5,
              ),
            ),
          ),
        Text(
          '按设备当地日期、标准双休计算。搜索未来 120 天，连续假期最多 16 天，限 $_year 年内，不跨年推断。请假仍需单位批准。',
          style: const TextStyle(fontSize: 12, color: _muted, height: 1.5),
        ),
        if (papers.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (var i = 0; i < papers.length; i++)
                TextButton.icon(
                  onPressed: () => widget.client.openUrl(papers[i]),
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: Text(papers.length == 1 ? '查看官方安排' : '官方安排 ${i + 1}'),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _calendar(HolidaySchedule schedule, HolidayPlan? plan) {
    final first = DateTime.utc(_year, _month);
    final count = DateTime.utc(_year, _month + 1, 0).day;
    final offset = first.weekday - 1;
    final rows = ((offset + count) / 7).ceil();
    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            for (final name in ['一', '二', '三', '四', '五', '六', '日'])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Center(
                  child: Text(
                    name,
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                ),
              ),
          ],
        ),
        for (var row = 0; row < rows; row++)
          TableRow(
            children: [
              for (var col = 0; col < 7; col++)
                Builder(
                  builder: (context) {
                    final number = row * 7 + col - offset + 1;
                    if (number < 1 || number > count) {
                      return const SizedBox.shrink();
                    }
                    final date = DateTime.utc(_year, _month, number);
                    final adjustment = schedule.known
                        ? schedule.adjustment(date)
                        : null;
                    final rest = schedule.isRestDay(date);
                    final inPlan = plan?.contains(date) ?? false;
                    final today = date == _today;
                    final marker = adjustment == null
                        ? (rest == true ? '·' : '')
                        : (adjustment.isOffDay ? '休' : '班');
                    final color = adjustment?.isOffDay == false
                        ? const Color(0xFFECC48D)
                        : (rest == true ? _teal : Colors.white70);
                    final description = adjustment != null
                        ? '${adjustment.name}，${adjustment.isOffDay ? '放假' : '补班'}'
                        : (rest == null ? '调休安排待确认' : (rest ? '周末休息' : '工作日'));
                    return Tooltip(
                      message:
                          '${holidayDateKey(date)} $description${inPlan ? '，推荐连休区间' : ''}',
                      child: Semantics(
                        label:
                            '${holidayDateKey(date)}，$description${today ? '，今天' : ''}${inPlan ? '，推荐连休区间' : ''}',
                        excludeSemantics: true,
                        child: Container(
                          margin: const EdgeInsets.all(1),
                          padding: const EdgeInsets.symmetric(
                            vertical: 5,
                            horizontal: 1,
                          ),
                          decoration: BoxDecoration(
                            color: inPlan
                                ? _teal.withValues(alpha: .1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: today ? _teal : Colors.transparent,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$number',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: color,
                                  fontWeight: today
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                              ),
                              Text(
                                marker.isEmpty ? ' ' : marker,
                                style: TextStyle(fontSize: 9, color: color),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
      ],
    );
  }
}

String _shortDate(DateTime date) => '${date.month}/${date.day}';
String _range(DateTime start, DateTime end) =>
    '${_shortDate(start)} 至 ${_shortDate(end)}';

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title, detail;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2, right: 11),
        child: Icon(icon, color: _teal, size: 22),
      ),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              detail,
              style: const TextStyle(fontSize: 12, color: _muted, height: 1.5),
            ),
          ],
        ),
      ),
    ],
  );
}

class _Legend extends StatelessWidget {
  const _Legend(this.symbol, this.label, this.color);
  final String symbol, label;
  final Color color;
  @override
  Widget build(BuildContext context) =>
      Text('$symbol $label', style: TextStyle(fontSize: 11, color: color));
}
