#!/usr/bin/env python3
"""jammy-lease 운영 스크립트 (#45) — operator 역할(MFA) 전용."""
import argparse
import getpass
import sys
import time

import boto3
from botocore.exceptions import ClientError

TABLE = "jammy-lease"
LEASE_ID = "db-primary"
REGION = "ap-northeast-2"      # 리전 제한 Deny 때문에 명시
PROFILE = "jammy-operator"

NAMES = {"#h": "holder", "#e": "epoch", "#x": "expires_at", "#u": "updated_by", "#r": "reason"}


def table():
    return boto3.Session(profile_name=PROFILE, region_name=REGION).resource("dynamodb").Table(TABLE)


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


def main():
    p = argparse.ArgumentParser(description="jammy-lease 운영 (operator)")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("show", help="현재 lease 조회")

    s = sub.add_parser("init", help="첫 아이템 생성 (한 번만)")
    s.add_argument("--holder", choices=["A", "B"], required=True)
    s.add_argument("--reason", required=True)

    args = p.parse_args()
    {"show": cmd_show, "init": cmd_init}[args.cmd](table(), args)


if __name__ == "__main__":
    main()
