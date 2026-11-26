#!/usr/bin/env python3
"""jammy-lease 운영 스크립트 (#45) — operator 역할(MFA) 전용."""
import argparse
import getpass
import sys
import time
import os

import boto3
from botocore.exceptions import ClientError

TTL = 15       # 갱신 5초 × 3번
MARGIN = 5     # 시계 차이 여유

TABLE = "jammy-lease"
LEASE_ID = "db-primary"
REGION = "ap-northeast-2"      # 리전 제한 Deny 때문에 명시
PROFILE = "jammy-operator"

NAMES = {"#h": "holder", "#e": "epoch", "#x": "expires_at", "#u": "updated_by", "#r": "reason"}

def cond_update(t, update, cond, values, reject_msg):
    """조건부 쓰기 공통: 조건이 틀리면 거절 메시지로 종료."""
    used = update + cond
    try:
        r = t.update_item(
            Key={"lease_id": LEASE_ID},
            UpdateExpression=update,
            ConditionExpression=cond,
            ExpressionAttributeNames={k: v for k, v in NAMES.items() if k in used},  # 안 쓰는 별명이 있으면 DynamoDB가 오류
            ExpressionAttributeValues=values,
            ReturnValues="ALL_NEW",
        )
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            fail(reject_msg)
        raise
    i = r["Attributes"]
    print(f"성공: holder={i['holder']} epoch={i['epoch']}")

def table():
    # 환경 변수에 임시 자격 증명이 있으면 사용(MFA 재입력 없음), 없으면 프로필로 MFA
    profile = None if os.environ.get("AWS_SESSION_TOKEN") else PROFILE
    return boto3.Session(profile_name=profile, region_name=REGION).resource("dynamodb").Table(TABLE)

def get_lease(t):
    # 강한 일관성 읽기: 주인 판단은 항상 최신 값으로
    return t.get_item(Key={"lease_id": LEASE_ID}, ConsistentRead=True).get("Item")


def who():
    return f"operator:{getpass.getuser()}"


def fail(msg):
    print(f"거절: {msg}", file=sys.stderr)
    sys.exit(1)


def cmd_show(t, args):
    item = get_lease(t)
    if not item:
        print("아이템 없음 — init 필요")
        return
    left = int(item["expires_at"]) - int(time.time())
    state = f"유효 (남은 {left}초)" if left > 0 else f"만료 ({-left}초 지남)"
    print(f"holder={item['holder']} epoch={item['epoch']} {state}")
    print(f"updated_by={item.get('updated_by')} reason={item.get('reason')}")


def cmd_init(t, args):
    try:
        t.update_item(
            Key={"lease_id": LEASE_ID},
            UpdateExpression="SET #h=:h, #e=:e, #x=:x, #u=:u, #r=:r",
            ConditionExpression="attribute_not_exists(lease_id)",   # 없을 때만 생성
            ExpressionAttributeNames=NAMES,
            ExpressionAttributeValues={
                ":h": args.holder, ":e": 1,
                ":x": int(time.time()),          # 갱신자(agent)가 아직 없으니 만료 상태로 시작
                ":u": who(), ":r": args.reason,
            },
        )
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            fail("이미 lease가 있음 — init은 처음 한 번만")
        raise
    print(f"생성: holder={args.holder} epoch=1")

def cmd_renew(t, args):
    # 시험용: agent의 갱신을 흉내
    cond_update(t, "SET #x=:x", "#h=:h AND #e=:e",
                {":x": int(time.time()) + TTL, ":h": args.holder, ":e": args.epoch},
                "주인 또는 epoch 불일치")


def cmd_takeover(t, args):
    now = int(time.time())
    cond_update(t,
                "SET #h=:new, #e=#e+:one, #x=:x, #u=:u, #r=:r",
                "#e=:e AND #h<>:new AND #x<:limit",           # 만료 + 내가 본 epoch 그대로일 때만
                {":new": args.to, ":one": 1, ":x": now + TTL, ":u": who(), ":r": args.reason,
                 ":e": args.epoch, ":limit": now - MARGIN},
                "아직 만료 전이거나 epoch가 바뀜")


def cmd_switch(t, args):
    if args.holder == args.to:
        fail("같은 거점으로는 전환 불가")
    cond_update(t,
                "SET #h=:new, #e=#e+:one, #x=:x, #u=:u, #r=:r",
                "#h=:cur AND #e=:e",                          # 만료 여부와 무관, 주인·epoch 일치만
                {":new": args.to, ":one": 1, ":x": int(time.time()) + TTL, ":u": who(),
                 ":r": args.reason, ":cur": args.holder, ":e": args.epoch},
                "주인 또는 epoch 불일치")

def main():
    p = argparse.ArgumentParser(description="jammy-lease 운영 (operator)")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("show", help="현재 lease 조회")

    s = sub.add_parser("init", help="첫 아이템 생성 (한 번만)")
    s.add_argument("--holder", choices=["A", "B"], required=True)
    s.add_argument("--reason", required=True)

    s = sub.add_parser("renew", help="시험용 갱신")
    s.add_argument("--holder", choices=["A", "B"], required=True)
    s.add_argument("--epoch", type=int, required=True)

    s = sub.add_parser("takeover", help="인수 (만료 후)")
    s.add_argument("--to", choices=["A", "B"], required=True)
    s.add_argument("--epoch", type=int, required=True, help="show로 확인한 현재 epoch")
    s.add_argument("--reason", required=True)

    s = sub.add_parser("switch", help="계획 전환 (failback 등)")
    s.add_argument("--holder", choices=["A", "B"], required=True, help="현재 주인")
    s.add_argument("--to", choices=["A", "B"], required=True)
    s.add_argument("--epoch", type=int, required=True)
    s.add_argument("--reason", required=True)

    args = p.parse_args()
    cmds = {"show": cmd_show, "init": cmd_init, "renew": cmd_renew,
            "takeover": cmd_takeover, "switch": cmd_switch}
    cmds[args.cmd](table(), args)

if __name__ == "__main__":
    main()
